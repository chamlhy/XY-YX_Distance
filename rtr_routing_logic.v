// $Id: rtr_routing_logic.v 5188 2012-08-30 00:31:31Z dub $

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//==============================================================================
// routing logic for VC router
//==============================================================================

module rtr_routing_logic
  (router_address, sel_mc, sel_irc, dest_info, route_op, route_orc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of message classes (e.g. request, reply) ��Ϣ���������������󡢻�Ӧ
   parameter num_message_classes = 2;
   
   // nuber of resource classes (e.g. minimal, adaptive) ��Դ����������������޶ȣ�����Ӧ��
   parameter num_resource_classes = 2;
   
   // number of routers in each dimension ÿ��ά���е�·��������
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network �����е�ά����
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor) 
   //ÿ��·�����Ľڵ�����Ҳ���Ǽ���ϵ��
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension 
   //ÿ��ά���ڵ�������//�������� 0mesh�� 1torus 2ȫ���ӣ�Ĭ��
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // select routing function type ѡ��·�ɹ������� 0ά��˳��·�ɣ�Ĭ��
   parameter routing_type = `ROUTING_TYPE_XYYX;
   
   // select order of dimension traversal 
   //ѡ�����ά�ȵ�˳�� 0����� 1���� 2������Ϣ����
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width required to select individual message class 
   //ѡ�񵥸���Ϣ��������
   localparam message_class_idx_width = clogb(num_message_classes);
   
   // width required to select individual router in a dimension
   //��һ��ά����ѡ�񵥸�·��������Ŀ��
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   //����������ѡ�񵥸�·��������Ŀ��
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   //�ڵ�ǰ·������ѡ�񵥸��ڵ�����Ŀ��
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // total number of bits required for storing routing information
   //�洢·����Ϣ��Ҫ��������λ��
   localparam dest_info_width
     = ((routing_type == `ROUTING_TYPE_PHASED_DOR) || (routing_type == `ROUTING_TYPE_XYYX)) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   
   // width of global addresses ȫ����ַ�Ŀ��
   localparam addr_width = router_addr_width + node_addr_width;
   
   // number of adjacent routers in each dimension ÿ��ά�����ھ�·����������
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router //·��������������˿ڵ�����
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // number of network-facing ports on router (i.e., w/o inject/eject ports)
   //·��������������Ķ˿���
   localparam num_network_ports = num_ports - num_nodes_per_router;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   // current router's address ��ǰ·������ַ
   input [0:router_addr_width-1] router_address;
   
   // select current message class ѡ��ǰ��Ϣ��
   input [0:num_message_classes-1] sel_mc;
   
   // select current resource class ѡ��ǰ��Դ��
   input [0:num_resource_classes-1] sel_irc;
   
   // routing data ·������
   input [0:dest_info_width-1]     dest_info;
   
   // output port to forward to Ҫת����������˿�
   output [0:num_ports-1] 	    route_op;
   wire [0:num_ports-1] 	    route_op;
   
   // select outgoing resource class ѡ�������Դ��
   output [0:num_resource_classes-1] route_orc;
   wire [0:num_resource_classes-1]   route_orc;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   //ǰ���λ����ָ����˿ڣ������͵�����·����
   wire [0:num_network_ports-1]      route_onp;
   assign route_op[0:num_network_ports-1] = route_onp; 
   
   wire [0:num_resource_classes*num_network_ports-1] route_orc_onp;
   wire 					     eject;
   
   generate
      
    case(routing_type)
	
	`ROUTING_TYPE_PHASED_DOR:
	  begin
	     
	     // all router addresses (intermediate + final) 
		 //���е�·������ַ���м���Լ�����
	     wire [0:num_resource_classes*
		   router_addr_width-1] dest_router_addr_irc;
	     assign dest_router_addr_irc
	       = dest_info[0:num_resource_classes*router_addr_width-1];
	     
	     wire [0:num_resource_classes-1] reached_dest_irc;
	     
	     genvar 			     irc;
	     
	     for(irc = 0; irc < num_resource_classes; irc = irc + 1)
	       begin:ircs
		  
		  // address of destination router for current resource class 
		  //��ǰ��Դ���Ŀ��·�����ĵ�ַ
		  wire [0:router_addr_width-1] dest_router_addr;
		  assign dest_router_addr
		    = dest_router_addr_irc[irc*router_addr_width:
					   (irc+1)*router_addr_width-1];
		  
		  wire [0:num_network_ports-1] route_onp;
		  
		  wire [0:num_dimensions-1]    addr_match_d;
		  
		  genvar 		       dim;
		  
		  for(dim = 0; dim < num_dimensions; dim = dim + 1)
		    begin:dims
		       
		       wire [0:dim_addr_width-1] dest_dim_addr;
		       assign dest_dim_addr
			 = dest_router_addr[dim*dim_addr_width:
					    (dim+1)*dim_addr_width-1];
		       
		       wire [0:dim_addr_width-1] curr_dim_addr;
		       assign curr_dim_addr
			 = router_address[dim*dim_addr_width:
					  (dim+1)*dim_addr_width-1];
		       
		       wire 			 dest_lt_curr;
		       wire [0:dim_addr_width-1] dest_minus_curr;
		       assign {dest_lt_curr, dest_minus_curr}
			 = dest_dim_addr - curr_dim_addr;
		       
		       wire 			 curr_lt_dest;
		       wire [0:dim_addr_width-1] curr_minus_dest;
		       assign {curr_lt_dest, curr_minus_dest}
			 = curr_dim_addr - dest_dim_addr;
		       
			   //��ͬάʱ�����Ϊ1����ͬά�����Ϊ0
		       assign addr_match_d[dim] = ~dest_lt_curr & ~curr_lt_dest;
		       
		       wire 			 dim_sel;
		       
		       case(dim_order)
			 //����
			 `DIM_ORDER_ASCENDING:
			   begin
			   //0άʱdim_sel��Ϊ1��
			   //��0άʱ����ǰ��άδͬά��dim_sel���Ϊ0����ά·�ɽ��Ϊ00
			   //��ǰ��ά��ͬά��Ϊ1����ά����·��
			      if(dim == 0)
				assign dim_sel = 1'b1;
			      else
				assign dim_sel = &addr_match_d[0:dim-1];
			   end
			 //����
			 `DIM_ORDER_DESCENDING:
			   begin
			      if(dim == (num_dimensions - 1))
				assign dim_sel = 1'b1;
			      else
				assign dim_sel
				  = &addr_match_d[dim+1:num_dimensions-1];
			   end
			 //�����
			 `DIM_ORDER_BY_CLASS:
			   begin
			      
			      wire mc_even;
			      
			      if(num_message_classes == 1)
				assign mc_even = 1'b1;
			      else if(num_message_classes > 1)
				begin
				   
				   wire [0:message_class_idx_width-1] mcsel;
				   c_encode
				     #(.num_ports(num_message_classes))
				   mcsel_enc
				     (.data_in(sel_mc),
				      .data_out(mcsel));
				   
				   assign mc_even
				     = ~mcsel[message_class_idx_width-1];
				   
				end
			      
			      if(num_dimensions == 1)
				assign dim_sel = 1'b1;
			      else if(dim == 0)
				assign dim_sel
				  = &addr_match_d[1:num_dimensions-1] | 
				    mc_even;
			      else if(dim == (num_dimensions - 1))
				assign dim_sel
				  = &addr_match_d[0:num_dimensions-2] | 
				    ~mc_even;
			      else
				assign dim_sel
				  = mc_even ? 
				    &addr_match_d[0:dim-1] : 
				    &addr_match_d[dim+1:num_dimensions-1];
			      
			   end
			 
		       endcase
		       
		       wire [0:num_neighbors_per_dim-1] 	      port_dec;
		       
		       case(connectivity)
			 
			 `CONNECTIVITY_LINE:
			   begin
			      //��ǰ01�����10������00
			      assign port_dec = {dest_lt_curr, curr_lt_dest};
			      
			   end
			 
			 `CONNECTIVITY_RING:
			   begin
			      
			      // In cases where the destination is equally far 
			      // away in either direction, we need some kind of 
			      // tie breaker to avoid load imbalance; one 
			      // simple solution is to break the tie based on 
			      // whether the current router's address is even 
			      // or odd.
			      // NOTE: This can create load imbalance when using
			      // concentration, as all nodes sharing a router 
			      // will pick the same direction.
			      wire tie_break;
			      assign tie_break
				= curr_dim_addr[dim_addr_width-1];
			      
			      // multiply by 2 and add tiebreaker x2�����tiebreaker
			      
			      wire [0:dim_addr_width] dest_minus_curr_x2;
			      assign dest_minus_curr_x2
				= {dest_minus_curr, tie_break};
			      
			      wire [0:dim_addr_width] curr_minus_dest_x2;
			      assign curr_minus_dest_x2
				= {curr_minus_dest, ~tie_break};
			      
			      wire 		      dest_minus_curr_gt_half;
			      assign dest_minus_curr_gt_half
				= dest_minus_curr_x2 > num_routers_per_dim;
			      
			      wire 		      curr_minus_dest_gt_half;
			      assign curr_minus_dest_gt_half
				= curr_minus_dest_x2 > num_routers_per_dim;
			      
			      wire 		      route_down;
			      assign route_down
				= (curr_lt_dest & dest_minus_curr_gt_half) |
				  (dest_lt_curr & ~curr_minus_dest_gt_half);
			      
			      wire 		      route_up;
			      assign route_up
				= (curr_lt_dest & ~dest_minus_curr_gt_half) |
				  (dest_lt_curr & curr_minus_dest_gt_half);
			      
			      assign port_dec = {route_down, route_up};
			      
			   end
			 
			 `CONNECTIVITY_FULL:
			   begin
			      
			      wire [0:num_routers_per_dim-1] port_sel_up;
			      c_decode
				#(.num_ports(num_routers_per_dim))
			      port_sel_up_dec
				(.data_in(dest_minus_curr),
				 .data_out(port_sel_up));
			      
			      wire [0:num_routers_per_dim-1] port_sel_down_rev;
			      c_decode
				#(.num_ports(num_routers_per_dim))
			      port_sel_down_rev_dec
				(.data_in(curr_minus_dest),
				 .data_out(port_sel_down_rev));
			      
			      wire [0:num_routers_per_dim-1] port_sel_down;
			      c_reverse
				#(.width(num_routers_per_dim))
			      port_sel_down_revr
				(.data_in(port_sel_down_rev),
				 .data_out(port_sel_down));
			      
			      wire [0:num_neighbors_per_dim-1] port_dec_up;
			      assign port_dec_up
				= port_sel_up[1:num_routers_per_dim-1];
			      
			      wire [0:num_neighbors_per_dim-1] port_dec_down;
			      assign port_dec_down
				= port_sel_down[0:num_routers_per_dim-2];
			      
			      c_select_mofn
				#(.num_ports(2),
				  .width(num_neighbors_per_dim))
			      port_dec_sel
				(.select({dest_lt_curr, curr_lt_dest}),
				 .data_in({port_dec_down, port_dec_up}),
				 .data_out(port_dec));
			      
			   end
			 
		       endcase
		       
		       assign route_onp[dim*num_neighbors_per_dim:
					(dim+1)*num_neighbors_per_dim-1]
			 = port_dec & {num_neighbors_per_dim{dim_sel}};
		       
		    end
		  
		  
		  assign route_orc_onp[irc*num_network_ports:
				       (irc+1)*num_network_ports-1]
		    = route_onp;
		  
		  assign reached_dest_irc[irc] = &addr_match_d;
		  
	       end
	     
	     if(num_resource_classes == 1)
	       begin
		  assign eject = reached_dest_irc;
		  assign route_orc = 1'b1;
	       end
	     else
	       begin
		  
		  wire [0:num_resource_classes-1] class_done_irc;
		  assign class_done_irc = sel_irc & reached_dest_irc;
		  
		  wire inc_rc;
		  assign inc_rc = |class_done_irc[0:num_resource_classes-2];
		  
		  assign eject = class_done_irc[num_resource_classes-1];
		  
		  assign route_orc = inc_rc ?
				     {1'b0, sel_irc[0:num_resource_classes-2]} :
				     sel_irc;
		  
	       end
	     
	  end
	
	
	`ROUTING_TYPE_XYYX:
	  begin//*/
	     
	     // all router addresses (intermediate + final) 
		 //���е�·������ַ���м���Լ�����
	     wire [0:num_resource_classes*
		   router_addr_width-1] dest_router_addr_irc;
	     assign dest_router_addr_irc
	       = dest_info[0:num_resource_classes*router_addr_width-1];
	     
	     wire [0:num_resource_classes-1] reached_dest_irc;
	     
	     genvar 			     irc;
	     
	     for(irc = 0; irc < num_resource_classes; irc = irc + 1)
	       begin:ircs
		  
		  // address of destination router for current resource class 
		  //��ǰ��Դ���Ŀ��·�����ĵ�ַ
		  wire [0:router_addr_width-1] dest_router_addr;
		  assign dest_router_addr
		    = dest_router_addr_irc[irc*router_addr_width:
					   (irc+1)*router_addr_width-1];
		  
		  wire [0:num_network_ports-1] route_onp;
		  
		  wire [0:num_dimensions-1]    addr_match_d;
		  
		  //��ȡX��Y��ֵ
		  //x
		  wire [0:dim_addr_width-1] dest_dim_addr_x;
		  assign dest_dim_addr_x
			= dest_router_addr[0:dim_addr_width-1];
		       
		  wire [0:dim_addr_width-1] curr_dim_addr_x;
		  assign curr_dim_addr_x
			= router_address[0:dim_addr_width-1];
		       
		  wire 			 dest_lt_curr_x;
		  wire [0:dim_addr_width-1] dest_minus_curr_x;
		  assign {dest_lt_curr_x, dest_minus_curr_x}
			= dest_dim_addr_x - curr_dim_addr_x;
		       
		  wire 			 curr_lt_dest_x;
		  wire [0:dim_addr_width-1] curr_minus_dest_x;
		  assign {curr_lt_dest_x, curr_minus_dest_x}
			= curr_dim_addr_x - dest_dim_addr_x;
		
		  //y
		  wire [0:dim_addr_width-1] dest_dim_addr_y;
		  assign dest_dim_addr_y
			= dest_router_addr[dim_addr_width:2*dim_addr_width-1];
		       
		  wire [0:dim_addr_width-1] curr_dim_addr_y;
		  assign curr_dim_addr_y
			= router_address[dim_addr_width:2*dim_addr_width-1];
		       
		  wire 			 dest_lt_curr_y;
		  wire [0:dim_addr_width-1] dest_minus_curr_y;
		  assign {dest_lt_curr_y, dest_minus_curr_y}
			= dest_dim_addr_y - curr_dim_addr_y;
		       
		  wire 			 curr_lt_dest_y;
		  wire [0:dim_addr_width-1] curr_minus_dest_y;
		  assign {curr_lt_dest_y, curr_minus_dest_y}
			= curr_dim_addr_y - dest_dim_addr_y;		
		  
		  //��ͬάʱ�����Ϊ1����ͬά�����Ϊ0
		  assign addr_match_d[0] = ~dest_lt_curr_x & ~curr_lt_dest_x;
		  assign addr_match_d[1] = ~dest_lt_curr_y & ~curr_lt_dest_y;
		  
		  //ά��ѡ���ź�
		  //����άʱdim_sel��Ϊ1��
		  //������άʱ��������άδͬά��dim_sel���Ϊ0����ά·�ɽ��Ϊ00
		  //������ά��ͬά��Ϊ1����ά����·��
		  wire [0:num_dimensions-1]	   dim_sel;
		  
		  //XY
		  //assign dim_sel[0] = 1'b1;
		  //assign dim_sel[1] = addr_match_d[0];
		  //YX
		  //assign dim_sel[0] = addr_match_d[1];
		  //assign dim_sel[1] = 1'b1;
		  
		  
		  /*//��żXY-YX
		  wire is_odd;
		  assign is_odd = router_address[dim_addr_width : 2*dim_addr_width-1] % 2;
		  
		  assign dim_sel[0]= curr_lt_dest_x ^~ is_odd | addr_match_d[1];
		  assign dim_sel[1]= curr_lt_dest_x ^ is_odd | addr_match_d[0];//*/
		  
		 //����XY-YX ����������
		  wire x_lt_y;
		  wire [0:dim_addr_width-1] x_minus_y;
		  assign {x_lt_y , x_minus_y}
		  =((dest_dim_addr_x - curr_dim_addr_x) - (dest_dim_addr_y - curr_dim_addr_y));
		  
		  assign dim_sel[0]= ~x_lt_y | addr_match_d[1];
		  assign dim_sel[1]= x_lt_y | addr_match_d[0];//*/

		  wire [0:num_neighbors_per_dim-1] 	      port_dec_x;
		  wire [0:num_neighbors_per_dim-1] 	      port_dec_y;
		  
		  assign port_dec_x = {dest_lt_curr_x, curr_lt_dest_x};
		  assign port_dec_y = {dest_lt_curr_y, curr_lt_dest_y};

		  
		  assign route_onp[0:num_neighbors_per_dim-1]
			= port_dec_x & {num_neighbors_per_dim{dim_sel[0]}};
			assign route_onp[num_neighbors_per_dim:2*num_neighbors_per_dim-1]
			= port_dec_y & {num_neighbors_per_dim{dim_sel[1]}};
		  
		  
		  assign route_orc_onp[irc*num_network_ports:
				       (irc+1)*num_network_ports-1]
		    = route_onp;
		  
		  assign reached_dest_irc[irc] = &addr_match_d;
		  
	     
	     if(num_resource_classes == 1)
	       begin
		  assign eject = reached_dest_irc;
		  assign route_orc = 1'b1;
	       end
	     else
	       begin
		  
		  wire [0:num_resource_classes-1] class_done_irc;
		  assign class_done_irc = sel_irc & reached_dest_irc;
		  
		  wire inc_rc;
		  assign inc_rc = |class_done_irc[0:num_resource_classes-2];
		  
		  assign eject = class_done_irc[num_resource_classes-1];
		  
		  assign route_orc = inc_rc ?
				     {1'b0, sel_irc[0:num_resource_classes-2]} :
				     sel_irc;
		  
	       end
	    end
	  end
	
      endcase
      
   endgenerate
   
   c_select_1ofn
     #(.num_ports(num_resource_classes),
       .width(num_network_ports))
   route_onp_sel
     (.select(route_orc),
      .data_in(route_orc_onp),
      .data_out(route_onp));
   
   generate
      //ѡ��·�����Ľڵ�
      if(num_nodes_per_router == 1)
	assign route_op[num_ports-1] = eject;
      else if(num_nodes_per_router > 1)
	begin
	   
	   wire [0:node_addr_width-1] dest_node_address;
	   assign dest_node_address
	     = dest_info[dest_info_width-node_addr_width:dest_info_width-1];
	   
	   wire [0:num_nodes_per_router-1] node_sel;
	   c_decode
	     #(.num_ports(num_nodes_per_router))
	   node_sel_dec
	     (.data_in(dest_node_address),
	      .data_out(node_sel));
	   
	   assign route_op[num_ports-num_nodes_per_router:num_ports-1]
		    = node_sel & {num_nodes_per_router{eject}};
	   
	end
      
   endgenerate
   
endmodule
