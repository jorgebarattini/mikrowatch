#Mikrotik Netwatch-like script
#Version 1.0
#Description: Script that monitors multiple IPs and
#enables/disables the gateway depending on PacketLoss and
#Latency.
#For this script to work you will need the following:
#  -The gateway route must have a comment and the variable
#   $mongateway must be set with the contents of this comment
#  -The dst-nat rules applied to this provider must have the
#   following specific comment:
#         NAT_VoIP_$admnameprov
#  -The monitored IPs must have a specific route through the
#   gateway of the monitored provider and a blackhole route with
#   greater distance to avoid responses over another provider
#The variables between lines MODIFY FOR EACH CLIENT must be set 
#accrodingly to the client and monitored IPs parameters
#
# ToDo:
#  -Automate provider gateway and nat detection just asking
#   provider name and gateway
#  -Check or force traffic for the monitored IPs through monitored
#   gateway

{
  ##########MODIFY FOR EACH CLIENT##########
  #Administrative parameters
  #Client name
  :local admadmnamecli "MYHAPPYCLIENT";
  #Name of interface
  :local admadmnamewan "WAN1";
  #Name of ISP
  :local admnameprov "MYISP";
  #Monitoring parameters
  #Number of pings to run each pass (two packets per ping)
  :local monpingcount 5;
  #Max latency accepted (in miliseconds)
  :local monpinglatency "500ms";
  #Number of passes to delare link up/down
  :local monpasses 2;
  #Array of monitored IPs
  #:local monips {8.8.8.8;8.8.4.4};
  :local monips {8.8.8.8};
  #IP of PBX server to reset conections
  :local monpbxip "192.168.1.114";
  #Configured comment on monitored Gateway (this
  #must be already set for script to work)
  :local mongateway "DG_WAN1-MYISP";
  #Notification parameters
  #Notify to email
  :local emaildst "my.email.address@gmail.com";
  ###########MODIFY FOR EACH CLIENT##########
  
  ###Operational parameters, do not modify###
  #Status of checks
  :local monstat {up};
  #Flag for usage of /tool flood-ping
  :global floodpinguse;
  #Initialize variables for FloodPing
  :local avgrttT value=0;
  :local sendT value=0;
  :local recvT value=0;
  #Initialize pass counter
  :local montime value=0;
  #Enable/disable debug
  :local endebug true;
  #Stored status of last checks
  :global monglobstat {down=0;up=0}
  #Date and time
  :local date [/system clock get date];
  :local time [/system clock get time];

  ################SCRIPT STARTS####################

  #Loop monitored IPs with flood-ping
  :foreach arrip in=$monips do={
    :for flooding from=1 to=$monpingcount step=1 do={
	  while ($floodpinguse = true) do={
	    if ($endebug = true) do={
		  :log warning "flood-ping busy, waiting 1 second";
		  delay 1s;
		}
	  }
	  :set floodpinguse true;
	  {
      /tool flood-ping count=2 timeout=$monpinglatency size=500 address=$arrip do={
        :if ($sent = 2) do={
		  :set avgrttT ($"avg-rtt" + $avgrttT);
		  :set sendT ($"sent" + $sendT);
		  :set recvT ($"received" + $recvT);
		}
      }
	  :set floodpinguse false;
      /delay 1s;
	  }
    }
	if ($endebug = true) do={ :log warning ("Monitor: ".$arrip." Avg. latency: ".[:tostr ($avgrttT / $monpingcount )]." ms PktSent: ".$sendT." PktRcvd: ".$recvT." PL: ".[:tostr (100-(($recvT*100)/($sendT)))]."%" ) };
    #Reset ping counters
    :set avgrttT value=0;
    :set sendT value=0;
    :set recvT value=0;
    #Check PL and Latency
	if (((100-(($recvT*100)/($sendT))) > $monpl) or (($avgrttT / $monpingcount ) > $monpinglatency) do={
	  #Link failed
	  :set monstat down;
      #Initialize comment if not created
	  if ([:pick [/ip route get [find comment~"$mongateway"] comment] ([:len [/ip route get [find comment~"$mongateway"] comment]]-1)] != "_") do={/ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_")};
	  #Check if stat changed
	  if ( [/ip route get [find comment~"$mongateway"] comment]~"-up" ) do={
	    #Status changed
		#Reset counter
		:set montime value=0;
		#Increase counter
		:set montime ($montime+1);
		#Write comment
		/ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_")
		if ($endebug = true) do={ :log warning ("Status changed from UP to DOWN. Comment set to: ".[/ip route get [find comment~"$mongateway"] comment] ) };
	  } else={
	    #Get how many times the state repeated
	    :set montime [:pick [/ip route get [find comment~"$mongateway"] comment] ([:len [/ip route get [find comment~"$mongateway"] comment]]-2)];
		#Check if Threshold is reached
		if ( $montime < $monpasses ) do={
          #Threshold no reached yet, increase counter
		  :set montime ($montime+1);
		  #And write to comment
		  /ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_");
		} else={
		  if ( $montime = $monpasses ) do={
		    #Threshold reached, disable gateway for this provider
		    /ip route set [find comment~"$mongateway"] disabled=yes;
			#Threshold reached, disable NATs for this provider
            /ip firewall nat disable [find comment="NAT_VoIP_$admnameprov"];
			#Threshold reached, kill all connections related to PBX for this provider
	        /ip firewall connection remove [find src-address~"$monpbxip"];
		    /ip firewall connection remove [find reply-src-address~"$monpbxip"];
			#Threshold reached, Send email
		    /tool e-mail send to="$emaildst" subject="$admnamecli - $admnamewan_$admnameprov - $monstat" body="Client: $admnamecli \n\n Date: $date, $time \n\n The $admnamewan Link $admnameprov at device $namedev is $monstat";
		    #Threshold reached, log warning
			:log warning "$admnameprov is $monstat, disabling DG for $admnameprov";
		    #Increase counter
		    :set montime ($montime+1);
		    #And write to comment
		    /ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_");
		  }
		}
	  }
	}
	else={
	  #Link OK
	  :set monstat up;
	  #Initialize comment if not created
	  if ([:pick [/ip route get [find comment~"$mongateway"] comment] ([:len [/ip route get [find comment~"$mongateway"] comment]]-1)] != "_") do={/ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_")};
	  #Check if stat changed
	  if ( [/ip route get [find comment~"$mongateway"] comment]~"-down" ) do={
	  	#Status changed
		#Reset counter
		:set montime value=0;
		#Increase counter
		:set montime ($montime+1);
		#Write comment
		/ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_")
		if ($endebug = true) do={ :log warning ("Status changed from DOWN to UP. Comment set to: ".[/ip route get [find comment~"$mongateway"] comment] ) };
	  }  else={
	    #Get how many times the state repeated
	    :set montime [:pick [/ip route get [find comment~"$mongateway"] comment] ([:len [/ip route get [find comment~"$mongateway"] comment]]-2)];
		#Check if Threshold is reached
		if ( $montime < $monpasses ) do={
          #Threshold no reached yet, increase counter
		  :set montime ($montime+1);
		  #And write to comment
		  /ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_");
		} else={
		  if ( $montime = $monpasses ) do={
		    #Threshold reached, enable gateway for this provider
		    /ip route set [find comment~"$mongateway"] disabled=no;
			#Threshold reached, enable NATs for this provider
            /ip firewall nat enable [find comment="NAT_VoIP_$admnameprov"];
			#Threshold reached, kill all connections related to PBX for this provider
	        /ip firewall connection remove [find src-address~"$monpbxip"];
		    /ip firewall connection remove [find reply-src-address~"$monpbxip"];
			#Threshold reached, Send email
		    /tool e-mail send to="$emaildst" subject="$admnamecli - $admnamewan_$admnameprov - $monstat" body="Client: $admnamecli \n\n Date: $date, $time \n\n The $admnamewan Link $admnameprov at device $namedev is $monstat";
		    #Threshold reached, log warning
			:log warning "$admnameprov is $monstat, enabling DG for $admnameprov";
		    #Increase counter
		    :set montime ($montime+1);
		    #And write to comment
		    /ip route set [find comment~"$mongateway"] comment=($mongateway."-".$monstat.$montime."_");
		  }
		}
	  }
	}
  }
}