#!/usr/bin/python

from scapy.all import Ether, IP, sendp, get_if_list, Raw, UDP
from scapy.config import conf
from time import sleep, time
import threading

# Configurações
src_mac = "00:00:00:00:01:01"
dst_mac = "00:00:00:00:02:02"
src_ip = "10.0.1.1"
dst_ip = "10.0.2.2"
data = "ABCDFE"
MAX_FLUXOS = 10 # limite de fluxos simultâneos
INTERVALO_FLUXOS = 5 # segundos entre criação de novos fluxos


interface = [i for i in get_if_list() if "eth0" in i][0]

def fluxo_thread(flow_id):
    s = conf.L2socket(iface=interface)
    sport = 10000 + (flow_id % 10000)
    dport = 20000 + (flow_id % 10000)

    p = Ether(dst=dst_mac, src=src_mac) / IP(frag=0, dst=dst_ip, src=src_ip)
    p = p / UDP(sport=sport, dport=dport) / Raw(load=data)

    pkt_cnt = 0
    last_sec = time()

    while True:
        s.send(p)
        pkt_cnt += 1

        if time() - last_sec >= 1.0:
            print("Fluxo :{}, Pkt/s: {}, Portas: {} {}".format(flow_id, pkt_cnt, sport, dport))
            pkt_cnt = 0
            last_sec = time()

if __name__ == "__main__":
    flow_id = 0
    while flow_id < MAX_FLUXOS:
        print("Novo fluxo :{}".format(flow_id))
        t = threading.Thread(target=fluxo_thread, args=(flow_id,))
        t.daemon = True
        t.start()

        flow_id += 1
        sleep(INTERVALO_FLUXOS)

    print("Total de fluxos atingido".format(MAX_FLUXOS))
    while True:
        sleep(1)
