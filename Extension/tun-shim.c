//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "Iodine.h"
#include "tun.h"

const CFStringRef IodineSetMTUNotification = CFSTR("IodineSetMTUNotification");
const CFStringRef IodineSetIPNotification = CFSTR("IodineSetIPNotification");
const CFStringRef kIodineMTU = CFSTR("MTU");
const CFStringRef kIodineClientIP = CFSTR("ClientIP");
const CFStringRef kIodineServerIP = CFSTR("ServerIP");
const CFStringRef kIodineSubnetMask = CFSTR("SubnetMask");

int open_tun(const char *tun_device) {
    fprintf(stderr, "Unimplemented function open_tun() called!\n");
    abort();
}

void close_tun(int tun_fd) {
    if (tun_fd > 0) {
        close(tun_fd);
    }
}

int write_tun(int tun_fd, char *data, size_t len) {
    return (int)write(tun_fd, data, len);
}

ssize_t read_tun(int tun_fd, char *data, size_t len) {
    return read(tun_fd, data, len);
}

static void AddIntegerValue(CFMutableDictionaryRef dictionary, const CFStringRef key, int32_t value)
{
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
    CFDictionaryAddValue(dictionary, key, number);
    CFRelease(number);
}

static void AddStringValue(CFMutableDictionaryRef dictionary, const CFStringRef key, const char *string)
{
    CFStringRef cfstr = CFStringCreateWithCString(kCFAllocatorDefault, string, kCFStringEncodingASCII);
    CFDictionaryAddValue(dictionary, key, cfstr);
    CFRelease(cfstr);
}

int tun_setip(const char *ip, const char *other_ip, int netbits) {
    int netmask;
    struct in_addr net;
    
    netmask = 0;
    for (int i = 0; i < netbits; i++) {
        netmask = (netmask << 1) | 1;
    }
    netmask <<= (32 - netbits);
    net.s_addr = htonl(netmask);
    CFNotificationCenterRef local = CFNotificationCenterGetLocalCenter();
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, NULL, NULL);
    AddStringValue(dict, kIodineClientIP, ip);
    AddStringValue(dict, kIodineServerIP, other_ip);
    AddStringValue(dict, kIodineSubnetMask, inet_ntoa(net));
    CFNotificationCenterPostNotification(local, IodineSetIPNotification, NULL, dict, TRUE);
    CFRelease(dict);
    return 0;
}

int tun_setmtu(const unsigned mtu) {
    CFNotificationCenterRef local = CFNotificationCenterGetLocalCenter();
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, NULL, NULL);
    AddIntegerValue(dict, kIodineMTU, mtu);
    CFNotificationCenterPostNotification(local, IodineSetMTUNotification, NULL, dict, TRUE);
    CFRelease(dict);
    return 0;
}
