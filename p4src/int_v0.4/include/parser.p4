/*
 * Copyright 2020-2021 PSNC, FBK
 *
 * Author: Damian Parniewicz, Damu Ding
 *
 * Created in the GN4-3 project.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

error
{
	INTShimLenTooShort,
	INTVersionNotSupported
}

#ifdef BMV2
 
parser ParserImpl(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

#elif TOFINO

parser IngressParser(packet_in packet, out headers hdr, out metadata meta, out ingress_intrinsic_metadata_t standard_metadata) {

#endif

    state start {
        #ifdef TOFINO
        packet.extract(standard_metadata);
        packet.advance(PORT_METADATA_SIZE);
        #endif
        transition parse_ethernet;
    }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            16w0x800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        meta.layer34_metadata.ip_src = hdr.ipv4.srcAddr;
        meta.layer34_metadata.ip_dst = hdr.ipv4.dstAddr;
        meta.layer34_metadata.ip_ver = 8w4;
        meta.layer34_metadata.dscp = hdr.ipv4.dscp;
        transition select(hdr.ipv4.protocol) {
            8w0x11: parse_udp;
            8w0x6: parse_tcp;
            default: accept;
        }
    }
    state parse_tcp {
        packet.extract(hdr.tcp);
        meta.layer34_metadata.l4_src = hdr.tcp.srcPort;
        meta.layer34_metadata.l4_dst = hdr.tcp.dstPort;
        meta.layer34_metadata.l4_proto = 8w0x6;
        transition select(meta.layer34_metadata.dscp) {
            IPv4_DSCP_INT: parse_int_shim;
            default: accept;
        }
    }
    state parse_udp {
        packet.extract(hdr.udp);
        meta.layer34_metadata.l4_src = hdr.udp.srcPort;
        meta.layer34_metadata.l4_dst = hdr.udp.dstPort;
        meta.layer34_metadata.l4_proto = 8w0x11;
        transition select(meta.layer34_metadata.dscp, hdr.udp.dstPort) {
            (6w0x20 &&& 6w0x3f, 16w0x0 &&& 16w0x0): parse_int_shim;
            default: accept;
        }
    }
    state parse_int_shim {
        packet.extract(hdr.int_shim);
        verify(hdr.int_shim.len >= 3, error.INTShimLenTooShort);
        transition parse_int_header;
    }
    state parse_int_header {
        packet.extract(hdr.int_header);
        verify(hdr.int_header.ver == INT_VERSION, error.INTVersionNotSupported);
        transition parse_int_data;
    }
    state parse_int_data {
        bit<8> int_headers_len_in_words = (bit<8>)(INT_ALL_HEADER_LEN_BYTES)>>2;
        bit<32> int_data_len_in_words = (bit<32>)(hdr.int_shim.len - int_headers_len_in_words);
        bit<32> int_data_len_in_bits =  int_data_len_in_words << 5;
        packet.extract(hdr.int_data, int_data_len_in_bits);
        transition parse_int_tail;
    }
    state parse_int_tail {
        packet.extract(hdr.int_tail);
        transition accept;
    }
}

#ifdef BMV2

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        // raport headers
        packet.emit(hdr.report_ethernet);
        packet.emit(hdr.report_ipv4);
        packet.emit(hdr.report_udp);
        packet.emit(hdr.report_fixed_header);
        
        // original headers
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.tcp);
        
        // INT headers
        packet.emit(hdr.int_shim);
        packet.emit(hdr.int_header);
        
        // local INT node metadata
        packet.emit(hdr.int_switch_id);
        packet.emit(hdr.int_port_ids);
        packet.emit(hdr.int_hop_latency);
        packet.emit(hdr.int_q_occupancy);
        packet.emit(hdr.int_ingress_tstamp);
        packet.emit(hdr.int_egress_tstamp);
        packet.emit(hdr.int_q_congestion);
        packet.emit(hdr.int_egress_port_tx_util);
        
        // other INT metadata 
        packet.emit(hdr.int_data);
        packet.emit(hdr.int_tail);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        update_checksum(
            hdr.ipv4.isValid(),
            {
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.dscp,
                hdr.ipv4.ecn,
                hdr.ipv4.totalLen,
                hdr.ipv4.id,
                hdr.ipv4.flags,
                hdr.ipv4.fragOffset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr
            },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16
        );
        
        update_checksum(
            hdr.report_ipv4.isValid(),
            {
                hdr.report_ipv4.version,
                hdr.report_ipv4.ihl,
                hdr.report_ipv4.dscp,
                hdr.report_ipv4.ecn,
                hdr.report_ipv4.totalLen,
                hdr.report_ipv4.id,
                hdr.report_ipv4.flags,
                hdr.report_ipv4.fragOffset,
                hdr.report_ipv4.ttl,
                hdr.report_ipv4.protocol,
                hdr.report_ipv4.srcAddr,
                hdr.report_ipv4.dstAddr
            },
            hdr.report_ipv4.hdrChecksum,
            HashAlgorithm.csum16
        );
        
        update_checksum_with_payload(
            hdr.udp.isValid(), 
            {  hdr.ipv4.srcAddr, 
                hdr.ipv4.dstAddr, 
                8w0, 
                hdr.ipv4.protocol, 
                hdr.udp.len, 
                hdr.udp.srcPort, 
                hdr.udp.dstPort, 
                hdr.udp.len 
            }, 
            hdr.udp.csum, 
            HashAlgorithm.csum16
        ); 

        update_checksum_with_payload(
            hdr.udp.isValid() && hdr.int_header.isValid() , 
            {  hdr.ipv4.srcAddr, 
                hdr.ipv4.dstAddr, 
                8w0, 
                hdr.ipv4.protocol, 
                hdr.udp.len, 
                hdr.udp.srcPort, 
                hdr.udp.dstPort, 
                hdr.udp.len,
                hdr.int_shim,
                hdr.int_header,
                hdr.int_tail,
                hdr.int_switch_id,
                hdr.int_port_ids,
                hdr.int_q_occupancy,
                hdr.int_q_congestion,
                hdr.int_ingress_tstamp,
                hdr.int_egress_tstamp,
                hdr.int_egress_port_tx_util,
                hdr.int_hop_latency
            }, 
            hdr.udp.csum, 
            HashAlgorithm.csum16
        );
    }
}

#elif TOFINO

/*********************  I N G R E S S   D E P A R S E R  ************************/

control IngressDeparser(packet_out packet, inout headers hdr, in metadata meta, in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Checksum() ipv4_csum;
    Checksum() udp_csum;
    Checksum() int_csum;
    apply {
        if(hdr.ipv4.isValid()){
            hdr.ipv4.hdrChecksum = ipv4_csum.update(
            {
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.dscp,
                hdr.ipv4.ecn,
                hdr.ipv4.totalLen,
                hdr.ipv4.id,
                hdr.ipv4.flags,
                hdr.ipv4.fragOffset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr
            });
        }
        
        if(hdr.udp.isValid()&& hdr.int_header.isValid() ){
            hdr.udp.csum= int_csum.update(
            data = {
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr,
                8w0,
                hdr.ipv4.protocol,
                hdr.udp.len,
                hdr.udp.srcPort,
                hdr.udp.dstPort,
                hdr.udp.len,
                hdr.int_shim,
                hdr.int_header,
                hdr.int_tail,
                hdr.int_switch_id,
                hdr.int_port_ids,
                hdr.int_q_occupancy,
                hdr.int_q_congestion,
                hdr.int_ingress_tstamp,
                hdr.int_egress_tstamp,
                hdr.int_egress_port_tx_util,
                hdr.int_hop_latency
            }, zeros_as_ones = true);
        }
        
        if(hdr.udp.isValid()){
            hdr.udp.csum= udp_csum.update(
                {hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr,
                8w0,
                hdr.ipv4.protocol,
                hdr.udp.len,
                hdr.udp.srcPort,
                hdr.udp.dstPort,
                hdr.udp.len
            });
        }
        
        // original headers
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.tcp);
        
        // INT headers
        packet.emit(hdr.int_shim);
        packet.emit(hdr.int_header);
        
        // local INT node metadata
        packet.emit(hdr.int_switch_id);
        packet.emit(hdr.int_port_ids);
        packet.emit(hdr.int_hop_latency);
        packet.emit(hdr.int_q_occupancy);
        packet.emit(hdr.int_ingress_tstamp);
        packet.emit(hdr.int_egress_tstamp);
        packet.emit(hdr.int_egress_port_tx_util);
        packet.emit(hdr.int_q_congestion);
        
        // other INT metadata 
        packet.emit(hdr.int_data);
        packet.emit(hdr.int_tail);
    }
}


/*********************  E G R E S S    D E P A R S E R  ************************/

control EgressDeparser(packet_out packet,
                                    /* User */
                                    inout headers                       hdr,
                                    in    metadata                      meta,
                                    /* Intrinsic */
                                    in    egress_intrinsic_metadata_for_deparser_t  eg_dprsr_md) {
    
    apply {
        // raport headers
        packet.emit(hdr.report_ethernet);
        packet.emit(hdr.report_ipv4);
        packet.emit(hdr.report_udp);
        packet.emit(hdr.report_fixed_header);
        
        // original headers
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.tcp);
        
        // INT headers
        packet.emit(hdr.int_shim);
        packet.emit(hdr.int_header);
        
        // local INT node metadata
        packet.emit(hdr.int_switch_id);
        packet.emit(hdr.int_port_ids);
        packet.emit(hdr.int_hop_latency);
        packet.emit(hdr.int_q_occupancy);
        packet.emit(hdr.int_ingress_tstamp);
        packet.emit(hdr.int_egress_tstamp);
        packet.emit(hdr.int_q_congestion);
        packet.emit(hdr.int_egress_port_tx_util);
        
        // other INT metadata 
        packet.emit(hdr.int_data);
        packet.emit(hdr.int_tail);
    }
}

#endif


