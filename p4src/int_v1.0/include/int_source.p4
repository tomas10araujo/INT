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

#ifdef BMV2
register<bit<16>>(1) hdr_seq_num_register;
register<bit<32>>(1) int_source_counter; // contador de pacotes
#elif TOFINO
Register<bit<16>, bit<16>>(1) hdr_seq_num_register;
Register<bit<32>, bit<32>>(1) int_source_counter;

RegisterAction<bit<16>, bit<16>, bit<16>>(hdr_seq_num_register)
    update_hdr_seq_num = {
        void apply(inout bit<16> value, out bit<16> result) {
            result = value;
            value = value + 1;
        }
    };
#endif

#ifdef BMV2
control Int_source(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
#elif TOFINO
control Int_source(inout headers hdr, inout metadata meta, in ingress_intrinsic_metadata_t standard_metadata, in ingress_intrinsic_metadata_from_parser_t imp) {
#endif

    action configure_source(bit<8> max_hop, bit<5> hop_metadata_len, bit<5> ins_cnt, bit<16> ins_mask) {
        hdr.int_shim.setValid();
        hdr.int_shim.int_type = INT_TYPE_HOP_BY_HOP;
        hdr.int_shim.len = (bit<8>)INT_ALL_HEADER_LEN_BYTES >> 2;

        hdr.int_header.setValid();
        hdr.int_header.ver = INT_VERSION;
        hdr.int_header.rep = 0;
        hdr.int_header.c = 0;
        hdr.int_header.e = 0;
        hdr.int_header.rsvd1 = 0;
        hdr.int_header.rsvd2 = 0;
        hdr.int_header.hop_metadata_len = hop_metadata_len;
        hdr.int_header.remaining_hop_cnt = max_hop;
        hdr.int_header.instruction_mask = ins_mask;

#ifdef BMV2
        hdr_seq_num_register.read(hdr.int_header.seq, 0);
        hdr_seq_num_register.write(0, hdr.int_header.seq + 1);
#elif TOFINO
        hdr.int_header.seq = update_hdr_seq_num.execute(0);
#endif

        hdr.int_shim.dscp = hdr.ipv4.dscp;
        hdr.ipv4.dscp = IPv4_DSCP_INT;
        hdr.ipv4.totalLen = hdr.ipv4.totalLen + INT_ALL_HEADER_LEN_BYTES;
        hdr.udp.len = hdr.udp.len + INT_ALL_HEADER_LEN_BYTES;
    }

    table tb_int_source {
        actions = {
            configure_source;
        }
        key = {
            hdr.ipv4.srcAddr     : ternary;
            hdr.ipv4.dstAddr     : ternary;
            meta.layer34_metadata.l4_src: ternary;
            meta.layer34_metadata.l4_dst: ternary;
        }
        size = 127;
    }

    action activate_source() {
        meta.int_metadata.source = 1;
    }

    table tb_activate_source {
        actions = {
            activate_source;
        }
        key = {
            standard_metadata.ingress_port: exact;
        }
        size = 255;
    }

    action set_sample_rate(bit<32> rate) {
        meta.int_metadata.sample_rate = rate;
    }

    table tb_sample_rate {
        actions = {
            set_sample_rate;
        }
        key = {
            hdr.ipv4.srcAddr     : ternary;
            hdr.ipv4.dstAddr     : ternary;
            meta.layer34_metadata.l4_src: ternary;
            meta.layer34_metadata.l4_dst: ternary;
        }
        size = 127;
        default_action = set_sample_rate(1); // envia header sempre
    }

    action read_pkt_counter() {
        int_source_counter.read(meta.int_metadata.pkt_counter, 0);
    }

    action increment_pkt_counter() {
        bit<32> tmp;
        int_source_counter.read(tmp, 0);
        tmp = tmp + 1;
        int_source_counter.write(0, tmp);
    }

    action reset_pkt_counter() {
        int_source_counter.write(0, 0);
    }

    apply {
#ifdef BMV2
        meta.int_metadata.ingress_tstamp = standard_metadata.ingress_global_timestamp;
        meta.int_metadata.ingress_port = (bit<16>)standard_metadata.ingress_port;
#elif TOFINO
        meta.int_metadata.setValid();
        meta.int_metadata.ingress_tstamp = imp.global_tstamp;
        meta.int_metadata.ingress_port = (bit<16>)standard_metadata.ingress_port;
#endif

        tb_activate_source.apply();

        if (meta.int_metadata.source == 1) {
            tb_sample_rate.apply();     // obter taxa de amostragem
            read_pkt_counter();         // ler o contador de pacotes

            if (meta.int_metadata.pkt_counter == meta.int_metadata.sample_rate - 1) {
                tb_int_source.apply();  // aplicar header INT
                reset_pkt_counter();
            } else {
                increment_pkt_counter(); // continuar a contar
            }
        }
    }
}
