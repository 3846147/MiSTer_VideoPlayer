// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer VideoPlayer ARM engine - RC1
#include "shared.hpp"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <alsa/asoundlib.h>
}

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <optional>
#include <queue>
#include <string>
#include <thread>
#include <vector>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

namespace fs = std::filesystem;
using namespace std::chrono_literals;

class SharedMem {
public:
    SharedMem() {
        fd_ = ::open("/dev/mem", O_RDWR | O_SYNC);
        if(fd_ < 0) throw std::runtime_error("open /dev/mem failed");
        base_ = static_cast<std::uint8_t*>(::mmap(nullptr, vp::MEM_LEN, PROT_READ|PROT_WRITE, MAP_SHARED, fd_, vp::MEM_BASE));
        if(base_ == MAP_FAILED) throw std::runtime_error("mmap /dev/mem failed");
    }
    ~SharedMem(){ if(base_ && base_ != MAP_FAILED) ::munmap(base_, vp::MEM_LEN); if(fd_>=0) ::close(fd_); }
    volatile std::uint64_t& q(std::size_t off){ return *reinterpret_cast<volatile std::uint64_t*>(base_+off); }
    std::uint16_t* fb(int n){ return reinterpret_cast<std::uint16_t*>(base_ + (n ? vp::OFF_FB1 : vp::OFF_FB0)); }
    bool coreAlive(std::uint32_t &last) {
        auto h=q(vp::OFF_HEART); auto magic=std::uint32_t(h>>32), cnt=std::uint32_t(h);
        bool ok=(magic==vp::HEART_MAGIC) && (cnt!=last); if(ok) last=cnt; return ok;
    }
    std::uint32_t joy0() const { auto p=reinterpret_cast<volatile const std::uint64_t*>(base_+vp::OFF_JOY); return std::uint32_t(*p); }
    std::uint64_t status0() const { return *reinterpret_cast<volatile const std::uint64_t*>(base_+vp::OFF_STATUS0); }
    std::uint64_t status1() const { return *reinterpret_cast<volatile const std::uint64_t*>(base_+vp::OFF_STATUS1); }
    std::uint64_t heartbeatRaw() const { return *reinterpret_cast<volatile const std::uint64_t*>(base_+vp::OFF_HEART); }
    void publish(int fb, bool valid, std::uint8_t state=1) {
        q(vp::OFF_CONTROL) = std::uint64_t(fb&1) | (std::uint64_t(valid)<<1) | (std::uint64_t(state)<<8);
        __sync_synchronize();
    }
private:
    int fd_=-1; std::uint8_t* base_=nullptr;
};

struct Options {
    int aspect=0; // 0 source,1 4:3,2 16:9,3 full
    int scale=0;  // 0 fit,1 fill,2 1:1,3 custom
    int seek=10;
    int autoNext=1;
};

static Options parseOptions(std::uint64_t s) {
    Options o;
    o.aspect=(s>>2)&3; o.scale=(s>>4)&3;
    static const int steps[4]={5,10,30,60}; o.seek=steps[(s>>6)&3];
    o.autoNext=(s>>8)&3; return o;
}

class AudioOut {
public:
    ~AudioOut(){ close(); }
    bool open48k(){
        if(snd_pcm_open(&pcm_, "default", SND_PCM_STREAM_PLAYBACK, 0)<0) return false;
        if(snd_pcm_set_params(pcm_, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                              2, 48000, 1, 100000)<0) { close(); return false; }
        return true;
    }
    void close(){ if(pcm_){ snd_pcm_drain(pcm_); snd_pcm_close(pcm_); pcm_=nullptr; } }
    void write(const std::int16_t* p, std::size_t frames, int volume){
        if(!pcm_) return;
        tmp_.assign(p,p+frames*2);
        float g=std::clamp(volume,0,100)/100.0f;
        for(auto &v:tmp_) v=std::int16_t(std::clamp(int(std::lround(v*g)),-32768,32767));
        const std::int16_t* cur=tmp_.data();
        while(frames){
            auto n=snd_pcm_writei(pcm_,cur,frames);
            if(n<0){ if(n==-EPIPE){ snd_pcm_prepare(pcm_); continue; } break; }
            cur += n*2; frames -= std::size_t(n);
        }
    }
    void drop(){ if(pcm_){ snd_pcm_drop(pcm_); snd_pcm_prepare(pcm_); } }
private:
    snd_pcm_t* pcm_=nullptr; std::vector<std::int16_t> tmp_;
};

enum class Nav { None, Prev, Next, Quit };

struct ControlState {
    std::atomic<bool> pause{false};
    std::atomic<int> volume{80};
    std::atomic<int> zoom{0};
    std::atomic<int> seekDelta{0};
    std::atomic<Nav> nav{Nav::None};
};

class InputPoller {
public:
    InputPoller(SharedMem& m, ControlState& c):mem_(m),ctl_(c){}
    void poll(const Options& o){
        auto raw=mem_.heartbeatRaw();
        auto magic=std::uint32_t(raw>>32), hc=std::uint32_t(raw);
        auto now=std::chrono::steady_clock::now();
        if(magic!=vp::HEART_MAGIC) { ctl_.nav=Nav::Quit; return; }
        if(hc!=lastHb_) { lastHb_=hc; lastHbTime_=now; }
        else if(now-lastHbTime_ > 750ms) { ctl_.nav=Nav::Quit; return; }
        auto j=mem_.joy0(); auto s1=mem_.status1();
        auto rising=j & ~lastJoy_; lastJoy_=j;
        auto tr=s1 & ~lastStatus1_; lastStatus1_=s1;
        // hps_io d-pad bits: 0 right, 1 left, 2 down, 3 up.
        if(rising&(1u<<0)) ctl_.seekDelta.fetch_add(o.seek);
        if(rising&(1u<<1)) ctl_.seekDelta.fetch_sub(o.seek);
        if(rising&(1u<<2)) ctl_.nav=Nav::Next;
        if(rising&(1u<<3)) ctl_.nav=Nav::Prev;
        // J1 buttons begin at bit 4 in the order declared in CONF_STR.
        if(rising&(1u<<4)) ctl_.pause=!ctl_.pause.load();
        if(rising&(1u<<5)) ctl_.volume=std::max(0,ctl_.volume.load()-5);
        if(rising&(1u<<6)) ctl_.volume=std::min(100,ctl_.volume.load()+5);
        if(rising&(1u<<7)) ctl_.zoom=std::max(-5,ctl_.zoom.load()-1);
        if(rising&(1u<<8)) ctl_.zoom=std::min(10,ctl_.zoom.load()+1);
        if(rising&(1u<<10)) ctl_.nav=Nav::Prev;
        if(rising&(1u<<11)) ctl_.nav=Nav::Next;
        // status[64+0] corresponds to status bit 64; triggers are bits 32..36,
        // therefore they live in status0, not status1. handled below.
        auto s0=mem_.status0(); auto tr0=s0 & ~lastStatus0_; lastStatus0_=s0;
        if(tr0&(1ULL<<32)) ctl_.pause=!ctl_.pause.load();
        if(tr0&(1ULL<<33)) ctl_.nav=Nav::Prev;
        if(tr0&(1ULL<<34)) ctl_.nav=Nav::Next;
        if(tr0&(1ULL<<35)) ctl_.seekDelta.fetch_sub(o.seek);
        if(tr0&(1ULL<<36)) ctl_.seekDelta.fetch_add(o.seek);
        (void)tr;
    }
private:
    SharedMem& mem_; ControlState& ctl_; std::uint32_t lastJoy_=0; std::uint64_t lastStatus0_=0,lastStatus1_=0;
    std::uint32_t lastHb_=0; std::chrono::steady_clock::time_point lastHbTime_=std::chrono::steady_clock::now();
};

static std::optional<std::string> selectedPath(){
    const char* p="/media/fat/config/VideoPlayer.s0";
    std::ifstream f(p); if(!f) return std::nullopt;
    std::string s; std::getline(f,s); if(!s.empty() && s.back()=='\r') s.pop_back();
    if(s.empty() || !fs::exists(s)) return std::nullopt; return s;
}

static std::vector<std::string> siblingVideos(const std::string& current){
    std::vector<std::string> v; fs::path d=fs::path(current).parent_path();
    for(auto &e:fs::directory_iterator(d)) if(e.is_regular_file()){
        auto x=e.path().extension().string(); std::transform(x.begin(),x.end(),x.begin(),::tolower);
        if(x==".avi"||x==".mp4"||x==".mkv"||x==".mov"||x==".mpg"||x==".mpeg"||x==".m4v") v.push_back(e.path().string());
    }
    std::sort(v.begin(),v.end()); return v;
}

class Decoder {
public:
    Decoder(SharedMem& m, ControlState& c):mem_(m),ctl_(c),input_(m,c){}
    Nav play(const std::string& path){
        AVFormatContext* fmt=nullptr; AVCodecContext *vc=nullptr,*ac=nullptr; SwsContext* sws=nullptr; SwrContext* swr=nullptr;
        AudioOut audio; int vst=-1,ast=-1; int shown=0, back=1; Nav result=Nav::None;
        if(avformat_open_input(&fmt,path.c_str(),nullptr,nullptr)<0) goto done;
        if(avformat_find_stream_info(fmt,nullptr)<0) goto done;
        for(unsigned i=0;i<fmt->nb_streams;i++){
            auto t=fmt->streams[i]->codecpar->codec_type;
            if(t==AVMEDIA_TYPE_VIDEO && vst<0) vst=i; if(t==AVMEDIA_TYPE_AUDIO && ast<0) ast=i;
        }
        if(vst<0) goto done;
        {
            const AVCodec* dec=avcodec_find_decoder(fmt->streams[vst]->codecpar->codec_id); if(!dec) goto done;
            vc=avcodec_alloc_context3(dec); avcodec_parameters_to_context(vc,fmt->streams[vst]->codecpar); if(avcodec_open2(vc,dec,nullptr)<0) goto done;
        }
        if(ast>=0){
            const AVCodec* dec=avcodec_find_decoder(fmt->streams[ast]->codecpar->codec_id);
            if(dec){ ac=avcodec_alloc_context3(dec); avcodec_parameters_to_context(ac,fmt->streams[ast]->codecpar); if(avcodec_open2(ac,dec,nullptr)<0){ avcodec_free_context(&ac); ac=nullptr; } }
        }
        if(ac && audio.open48k()){
            AVChannelLayout out{}; av_channel_layout_default(&out,2);
            swr_alloc_set_opts2(&swr,&out,AV_SAMPLE_FMT_S16,48000,&ac->ch_layout,ac->sample_fmt,ac->sample_rate,0,nullptr);
            if(!swr || swr_init(swr)<0){ if(swr) swr_free(&swr); }
            av_channel_layout_uninit(&out);
        }
        {
            AVPacket* pkt=av_packet_alloc(); AVFrame* fr=av_frame_alloc(); AVFrame* afr=av_frame_alloc();
            auto wall0=std::chrono::steady_clock::now(); double pts0=-1;
            bool eof=false;
            while(!eof){
                Options opt=parseOptions(mem_.status0()); input_.poll(opt);
                if(ctl_.nav.load()!=Nav::None){ result=ctl_.nav.exchange(Nav::None); break; }
                while(ctl_.pause.load()){
                    std::this_thread::sleep_for(10ms); input_.poll(opt);
                    if(ctl_.nav.load()!=Nav::None){ result=ctl_.nav.exchange(Nav::None); goto loop_done; }
                }
                int sd=ctl_.seekDelta.exchange(0);
                if(sd){
                    auto nowTs = (pts0<0?0:pts0) + sd;
                    std::int64_t ts=std::int64_t(nowTs / av_q2d(fmt->streams[vst]->time_base));
                    av_seek_frame(fmt,vst,ts,AVSEEK_FLAG_BACKWARD); avcodec_flush_buffers(vc); if(ac) avcodec_flush_buffers(ac); audio.drop(); pts0=-1; wall0=std::chrono::steady_clock::now();
                }
                int rr=av_read_frame(fmt,pkt); if(rr<0){ eof=true; av_packet_unref(pkt); break; }
                if(pkt->stream_index==vst){
                    if(avcodec_send_packet(vc,pkt)>=0) while(avcodec_receive_frame(vc,fr)>=0){
                        double pts=(fr->best_effort_timestamp==AV_NOPTS_VALUE ? 0 : fr->best_effort_timestamp*av_q2d(fmt->streams[vst]->time_base));
                        if(pts0<0){ pts0=pts; wall0=std::chrono::steady_clock::now(); }
                        auto target=wall0+std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(std::max(0.0,pts-pts0)));
                        while(std::chrono::steady_clock::now()+2ms<target){ std::this_thread::sleep_for(2ms); input_.poll(opt); if(ctl_.nav.load()!=Nav::None) break; }
                        render(fr,back,opt,sws); mem_.publish(back,true,1); back^=1; shown++;
                    }
                } else if(ac && swr && pkt->stream_index==ast){
                    if(avcodec_send_packet(ac,pkt)>=0) while(avcodec_receive_frame(ac,afr)>=0){
                        int outMax=av_rescale_rnd(swr_get_delay(swr,ac->sample_rate)+afr->nb_samples,48000,ac->sample_rate,AV_ROUND_UP);
                        audioBuf_.resize(std::size_t(outMax)*2); uint8_t* outp=reinterpret_cast<uint8_t*>(audioBuf_.data());
                        int n=swr_convert(swr,&outp,outMax,const_cast<const uint8_t**>(afr->extended_data),afr->nb_samples);
                        if(n>0) audio.write(audioBuf_.data(),n,ctl_.volume.load());
                    }
                }
                av_packet_unref(pkt);
            }
loop_done:
            av_frame_free(&afr); av_frame_free(&fr); av_packet_free(&pkt);
        }
done:
        if(sws) sws_freeContext(sws); if(swr) swr_free(&swr); if(vc) avcodec_free_context(&vc); if(ac) avcodec_free_context(&ac); if(fmt) avformat_close_input(&fmt);
        if(!shown) mem_.publish(0,false,0);
        return result;
    }
private:
    void render(AVFrame* src,int fb,const Options& opt,SwsContext*& sws){
        int sw=src->width, sh=src->height;
        double srcAR=double(sw)/std::max(1,sh);
        double ar=srcAR;
        if(opt.aspect==1) ar=4.0/3.0;
        else if(opt.aspect==2) ar=16.0/9.0;
        else if(opt.aspect==3) ar=double(vp::FB_W)/vp::FB_H;
        const double canvasAR=double(vp::FB_W)/vp::FB_H;

        int dw=vp::FB_W, dh=vp::FB_H;
        if(opt.scale==0 || opt.scale==3) { // Fit / Custom base
            if(ar>canvasAR) dh=std::max(1,int(std::lround(dw/ar)));
            else dw=std::max(1,int(std::lround(dh*ar)));
        } else if(opt.scale==1) { // Fill while preserving aspect; crop center.
            if(ar>canvasAR) dw=std::max(1,int(std::lround(dh*ar)));
            else dh=std::max(1,int(std::lround(dw/ar)));
        } else if(opt.scale==2) { // 1:1, bounded only by memory/sanity.
            dw=std::max(1,sw); dh=std::max(1,sh);
        }

        int z=ctl_.zoom.load();
        double zg=1.0+0.05*z;
        dw=std::clamp(int(std::lround(dw*zg)),1,1280);
        dh=std::clamp(int(std::lround(dh*zg)),1,960);

        sws=sws_getCachedContext(sws,sw,sh,(AVPixelFormat)src->format,dw,dh,
                                 AV_PIX_FMT_RGB565LE,SWS_BILINEAR,nullptr,nullptr,nullptr);
        temp_.resize(std::size_t(dw)*dh);
        uint8_t* dstData[4]={reinterpret_cast<uint8_t*>(temp_.data()),nullptr,nullptr,nullptr};
        int dstLines[4]={dw*2,0,0,0};
        sws_scale(sws,src->data,src->linesize,0,sh,dstData,dstLines);

        auto *dst=mem_.fb(fb);
        std::fill(dst,dst+vp::FB_W*vp::FB_H,0);
        int srcX=std::max(0,(dw-int(vp::FB_W))/2);
        int srcY=std::max(0,(dh-int(vp::FB_H))/2);
        int dstX=std::max(0,(int(vp::FB_W)-dw)/2);
        int dstY=std::max(0,(int(vp::FB_H)-dh)/2);
        int copyW=std::min<int>(vp::FB_W,dw);
        int copyH=std::min<int>(vp::FB_H,dh);
        for(int r=0;r<copyH;r++) {
            std::memcpy(dst+(dstY+r)*vp::FB_W+dstX,
                        temp_.data()+(srcY+r)*dw+srcX,
                        std::size_t(copyW)*2);
        }
        __sync_synchronize();
    }
    SharedMem& mem_; ControlState& ctl_; InputPoller input_; std::vector<std::uint16_t> temp_; std::vector<std::int16_t> audioBuf_;
};

static std::string chooseSibling(const std::string& cur, Nav n){
    auto v=siblingVideos(cur); if(v.empty()) return cur;
    auto it=std::find(v.begin(),v.end(),cur); std::size_t i=(it==v.end()?0:std::size_t(it-v.begin()));
    if(n==Nav::Next) i=(i+1)%v.size(); else if(n==Nav::Prev) i=(i+v.size()-1)%v.size(); return v[i];
}

int main(int argc,char**argv){
    (void)argc;(void)argv; av_log_set_level(AV_LOG_ERROR);
    try{
        SharedMem mem; ControlState ctl; Decoder dec(mem,ctl); std::uint32_t hb=0; std::string current, lastSelection;
        fs::create_directories("/media/fat/logs/VideoPlayer");
        for(;;){
            bool alive=false; for(int i=0;i<8;i++){ if(mem.coreAlive(hb)){alive=true;break;} std::this_thread::sleep_for(30ms); }
            if(!alive){ mem.publish(0,false,0); current.clear(); std::this_thread::sleep_for(250ms); continue; }
            if(auto p=selectedPath(); p && *p!=lastSelection) { lastSelection=*p; current=*p; }
            if(current.empty()){ std::this_thread::sleep_for(100ms); continue; }
            Nav n=dec.play(current); Options o=parseOptions(mem.status0());
            if(n==Nav::Prev||n==Nav::Next) current=chooseSibling(current,n);
            else if(n==Nav::Quit) current.clear();
            else { // EOF
                if(o.autoNext==0) { mem.publish(0,false,0); current.clear(); }
                else if(o.autoNext==2) { /* loop current */ }
                else current=chooseSibling(current,Nav::Next);
            }
        }
    }catch(const std::exception& e){ std::cerr<<"VideoPlayer: "<<e.what()<<"\n"; return 1; }
}
