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

#ifndef Iodine_h
#define Iodine_h

#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <time.h>

extern const CFNotificationName IodineSetMTUNotification;
extern const CFNotificationName IodineSetIPNotification;
extern const CFStringRef kIodineMTU;
extern const CFStringRef kIodineClientIP;
extern const CFStringRef kIodineSubnetMask;

static inline void iodine_srand(void) {
    srand((unsigned) time(NULL));
}

#endif /* Iodine_h */
