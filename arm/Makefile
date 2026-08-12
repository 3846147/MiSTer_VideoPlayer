CXX := arm-linux-gnueabihf-g++
PKG_CONFIG ?= arm-linux-gnueabihf-pkg-config
PREFIX ?= /opt/vp
CXXFLAGS += -O3 -std=c++17 -pthread -I$(PREFIX)/include
LDFLAGS += -static -pthread -L$(PREFIX)/lib
LIBS = -lavformat -lavcodec -lavutil -lswscale -lswresample -lasound -lm -ldl -lrt
all: VideoPlayer
VideoPlayer: src/main.cpp src/shared.hpp
	$(CXX) $(CXXFLAGS) src/main.cpp -o $@ $(LDFLAGS) $(LIBS)
clean:
	rm -f VideoPlayer
