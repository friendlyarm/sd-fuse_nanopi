# ----------------------------------------------------------
# Makefile for building tools
#
# Copyright 2013 FriendlyARM (http://www.arm9.net/)
# (http://www.friendlyarm.com)
#

CC		= gcc
RM		= rm

CFLAGS	= -Wall -O2 -static

TARGET	= sd_fdisk


# ----------------------------------------------------------

all: $(TARGET)

sd_fdisk: sd_fdisk.o
	$(CC) $(CFLAGS) $^ -o $@
	

clean:
	$(RM) -rf *.o $(TARGET)

distclean: clean
	$(RM) -rf *.vi~ *.orig


# ----------------------------------------------------------

.PHONY: $(PHONY) clean distclean

