#!/usr/bin/python

# Copyright 2020-2021 PSNC
# Author: Damian Parniewicz
#
# Created in the GN4-3 project.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from scapy.all import Ether, IP, sendp, get_if_hwaddr, get_if_list, TCP, Raw, UDP
from scapy.config import conf
import sys
from time import sleep, time

src_mac = "5c:b9:01:93:53:54"
data = "ABCDFE" 
src_ip = "150.254.169.196"
dst_mac = "00:10:db:ff:10:02"
dst_ip = "195.113.172.46"
sport = 0x11FF
dport = 0x22FF
dport = 0x4268 # 17000

interface = [i for i in get_if_list() if "eth0" in i][0]
s = conf.L2socket(iface=interface)

p = Ether(dst=dst_mac,src=src_mac)/IP(frag=0,dst=dst_ip,src=src_ip)
p = p/UDP(sport=sport, dport=dport)/Raw(load=data)

if __name__ == "__main__":
    pkt_cnt = 0
    last_sec = time()
    while True:
        #start = time()
        s.send(p)
        #print("Send time is %s", time()-start)
        #sleep(0.001)
        
        pkt_cnt += 1
        if time()-last_sec > 1.0:
            print("Pkt/s", pkt_cnt)
            pkt_cnt = 0
            last_sec = time()
