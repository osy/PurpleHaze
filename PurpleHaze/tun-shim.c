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

#include <stdio.h>
#include "tun.h"

int open_tun(const char *tun_device) {
    return -1;
}

void close_tun(int tun_fd) {
    
}

int write_tun(int tun_fd, char *data, size_t len) {
    return -1;
}

ssize_t read_tun(int tun_fd, char *data, size_t len) {
    return -1;
}

int tun_setip(const char *ip, const char *other_ip, int netbits) {
    return -1;
}

int tun_setmtu(const unsigned mtu) {
    return -1;
}
