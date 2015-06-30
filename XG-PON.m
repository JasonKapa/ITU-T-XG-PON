function [ Throughput, Mean_Frame_Delay ] = xGPON( T,N,Rm )
	%Start Time-watch(RealTime)
	tic
	%User Parameters 
	% T: Simulation time
	% N: Number of ONUs
	% Rm: Fixed Minimum bandwidth for each ONU
	Time = 0;
	Sim_Flag = true;
	%Add Guard time to start transmission time of ONU frame if time of transmission ends is equal 
	%to another frame transmission end time
	Guard_Time = 50 * 10^-6; %seconds
	%BWmap size is fixed to N*8 bytes
	BWmap_Size = 8*N;
	%Report message from ONU size
	Report_msg_Size = 64; %Bytes
	%Initialize Event_List
	Event_List = zeros(5,0);
	%Initialize Event1 that produce Ethernet frames to OLT buffer (10MB) for a
	%specific destination ONU_ID.
	for i=1:N
		Event_List(1,end+1) = 1;
		Event_List(2,end) = Time + poissrnd(2,1,1) * 10^-3; %seconds
		Event_List(3,end) = 2;%Second priority  
		Event_List(4,end) = i;%ONU_ID as receiver
	end
	%Initialize Event2 that produce Ethernet frames to each ONU buffer (10MB).
	for i=1:N
		Event_List(1,end+1) = 2;
		Event_List(2,end) = Time + poissrnd(1,1,1) * 10^-3; %seconds
		Event_List(3,end) = 2;%Second priority 
		Event_List(4,end) = i;%ONU_ID as transmitter
	end
	%Event 3 start at Time 0. OLT send Upstream frame : Data (30K) + BWmap Size
	Event_List(1,end+1) = 3;
	Event_List(2,end) = Time;
	Event_List(3,end) = 1; %First priority 
	%Event 5 end Simulation after T seconds
	Event_List(1,end+1) = 5;
	Event_List(2,end) = T;
	Event_List(3,end) = 4;
	%Buffer_Size size holds sum of bytes in each ONU's and OLT Buffer
	Buffer_Size = zeros(N+1,1);
	%Maximum Bytes for Buffer_Size -/- after that, frames will be dropped from Buffer
	Max_Buffer_Size = 10*10^3; %Bytes
	%ONU_Buffer_Occupancy holds all frames in ONU's Buffers 
	%Fields: Insertion Time, Size, ONU_ID(transmitter) and flag(0/1) 1 means frame transmitted
	ONU_Buffer_Occupancy = zeros(0,4);
	%OLT_Buffer_Occupancy holds only frames of OLT with different ONUs as destination
	%Fields: Insertion Time, Size, ONU_ID(receiver) and flag(0/1) 1 means frame transmitted
	OLT_Buffer_Occupancy = zeros(0,4);
	%Bytes_ONU_Asks holds total bytes each ONU has to send. OLT look this at that array to distribute bandwidth
	Bytes_ONU_Asks = zeros(N,1);
	%Holds Ending Time of transmission for each ONU 
	Ending_Times_of_Transmissions = zeros(1,N);
	%Calculate for each ONU random distance from OLT
	Distance = zeros(1,N);
	for i = 1:N
		Distance(1,i) = randi([20,60],1) * 10^3; %metres
	end
	%Transmission Speed 2/3 speed light
	V_transmit = 2/3*3*10^8; %metres/seconds
	%Calculate RTT/2 for each ONUs
	RTT_2 = zeros(1,N);
	for i = 1:N
		RTT_2(1,i) = Distance(1,i) / V_transmit;
	end

	%Statistics
	Throughput = 0;
	Total_Bytes_Sent = 0;
	Total_Waiting_Time = 0;
	Mean_Frame_Delay = 0;
	Total_Frames_Sent = 0;

	while Sim_Flag

			Event = Event_List(1,1);
			Time = Event_List(2,1);   

			if Event == 1
				[ Event_List, Buffer_Size, OLT_Buffer_Occupancy ] = Event1 ( Time, Event_List, Buffer_Size, Max_Buffer_Size, OLT_Buffer_Occupancy);
			elseif Event == 2
				[ Event_List, Buffer_Size, ONU_Buffer_Occupancy ] = Event2 ( Time, Event_List, Buffer_Size, Max_Buffer_Size, ONU_Buffer_Occupancy);
			elseif Event == 3
				[ Event_List, OLT_Buffer_Occupancy, Ending_Times_of_Transmissions, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size ] = Event3 ( Time, Event_List, Bytes_ONU_Asks, N, OLT_Buffer_Occupancy, ONU_Buffer_Occupancy, RTT_2, BWmap_Size, Rm, Guard_Time, Report_msg_Size, Ending_Times_of_Transmissions, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size );
			elseif Event == 4
				[ Event_List, ONU_Buffer_Occupancy, Bytes_ONU_Asks, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size ] = Event4 ( Time, Event_List, ONU_Buffer_Occupancy, Bytes_ONU_Asks, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size);
			elseif Event == 5
				[  Sim_Flag, Throughput, Mean_Frame_Delay ] = Event5 ( Time, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent );
			end

			Event_List(:,1)=[];
			Event_List=(sortrows(Event_List',[2,3]))';
			
	end
end
%Event1: Create Ethernet Frames and insert to OLT's buffer.Each Frames has a specific ONU ID for destination
function [ Event_List, Buffer_Size, OLT_Buffer_Occupancy ] = Event1 ( Time, Event_List, Buffer_Size, Max_Buffer_Size, OLT_Buffer_Occupancy)

	%Take ONU_ID 
    ONU_ID = Event_List(4,1);
    %Calculate a random size and insert frame in Buffer_Size
    %The size of Ethernet frame is between [64 - 1518]Bytes
    Frame_Size = randi([64,9000],1);
    sprintf('Event1 at Time %d -//- Ethernet Frame size %d bytes -//- Destination ONU %d', Time, Frame_Size, ONU_ID)

    %Check if OLT's Buffer has enough space for that Frame. (1,1) total bytes
    %in OLT buffer. 
    if (Buffer_Size(1,1) + Frame_Size) <= Max_Buffer_Size
                %Increase total Buffer_Size of OLT
                Buffer_Size(1,1) = Buffer_Size(1,1) + Frame_Size;
                %Insert info of that Frame to OLT's Buffer
				%Time of Insertion
                OLT_Buffer_Occupancy(end+1,1) = Time; 
                OLT_Buffer_Occupancy(end,2) = Frame_Size; 
                OLT_Buffer_Occupancy(end,3) = ONU_ID;
                sprintf('%d bytes are added to OLT Buffer Occupancy',Frame_Size)
            else
                disp('Maximum buffer Size.Frame dropped!')
    end
    %Event 1 call itself after poisson distribution time
    Event_List(1,end+1) = 1;
    Event_List(2,end) = Time + poissrnd(2,1,1) * 10^-3; %seconds
    Event_List(3,end) = 2;%Second priority 
    Event_List(4,end) = ONU_ID;%ONU_ID Destination
end
%Event2: Create Ethernet Frames and insert to ONU buffer.Each frame has a specific Transmitter ONU ID  
function [ Event_List, Buffer_Size, ONU_Buffer_Occupancy ] = Event2 ( Time, Event_List, Buffer_Size, Max_Buffer_Size, ONU_Buffer_Occupancy)

    %Take Receiver ONU_ID 
    ONU_ID = Event_List(4,1);
    %Calculate a random size for the frame and insert it in the specific ONU's Buffer Occupancy
    %The size of Ethernet frame is between [64 - 1518]Bytes
    Frame_Size = randi([64,9000],1);
	sprintf('Event2 at Time %d -//- Ethernet Frame size %d bytes -//- Transmitter ONU %d', Time, Frame_Size, ONU_ID)
    %Check if ONU's Buffer has enough space for that Frame.
    if (Buffer_Size(ONU_ID,1) + Frame_Size) <= Max_Buffer_Size
                %Increase Buffer size
                Buffer_Size(ONU_ID,1) = Buffer_Size(ONU_ID,1) + Frame_Size;
                %Insert info of that frame to ONU_Buffer_Occupancy
				%Time of insertion
                ONU_Buffer_Occupancy(end+1,1) = Time; 
                ONU_Buffer_Occupancy(end,2) = Frame_Size; 
                ONU_Buffer_Occupancy(end,3) = ONU_ID;
                sprintf('%d bytes are added to %d ONU Buffer_Size',Frame_Size,ONU_ID)
            else
                disp('Maximum buffer Size.Frame dropped!')
    end
    %Event 2 call itself after poisson distribution time
    Event_List(1,end+1) = 2;
    Event_List(2,end) = Time + poissrnd(1,1,1) * 10^-3; %seconds
    Event_List(3,end) = 2;%Second priority 
    Event_List(4,end) = ONU_ID;%ONU_ID
end
%Event3: Read ONU_Buffer_Occupancy of each ONU and share bandwidth:
%Give minimum Rm bytes to each ONU,
%then give remaining bandwidth starting from the first frame in ONU_Buffer_Occupancy. 
%Call Event 3 for each ONU then call itself after 125μseconds.
function [ Event_List, OLT_Buffer_Occupancy, Ending_Times_of_Transmissions, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size ] = Event3 ( Time, Event_List, Bytes_ONU_Asks, N, OLT_Buffer_Occupancy, ONU_Buffer_Occupancy, RTT_2, BWmap_Size, Rm, Guard_Time, Report_msg_Size, Ending_Times_of_Transmissions, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size )

    sprintf('Event3: OLT start Distributing Bandwidth at Time: %d', Time)    
    %Calculate Remaining_Bandwidth 2,5Gbps - Rm (Minimum Bytes) * N
    Remaining_Bandwidth = (2.5/8)*10^9;%Bytes
	%For Each ONU check
    for ONU_ID = 1:N
        %Hold Bytes OLT will send 
        Bytes_to_Send = 0;
	    %How many frames OLT_Buffer_Occupancy has for her, pick frames with total maximum 30KB
        %Bytes_to_Send <= 30KB
		%Hold row of each frame add to Bytes_to_Send 
        Frames_Removed = zeros(0,1);
        for frames = 1:size(OLT_Buffer_Occupancy,1)
			%If that frame is for that ONU and its not flagged as transmitted  
            if OLT_Buffer_Occupancy(frames,3) == ONU_ID && OLT_Buffer_Occupancy(frames,4) == 0
                if Bytes_to_Send + OLT_Buffer_Occupancy(frames,2) <= 30000
                    Bytes_to_Send = Bytes_to_Send + OLT_Buffer_Occupancy(frames,2);
					%flag that frame as transmitted
                    OLT_Buffer_Occupancy(frames,4) = 1;
                    %Calculate waiting time for this frame Time (now ) - Time of insertion in OLTs buffer
					%Add waiting time to total counter of packets delay
                    Total_Waiting_Time = Total_Waiting_Time + (Time - OLT_Buffer_Occupancy(frames,1));
                    Frames_Removed(end+1,1) = frames;
                    Total_Frames_Sent = Total_Frames_Sent + 1;
                else
                    break;
                end
            end
        end  
        %Remove all frames, that will be transmitted from Buffer
        OLT_Buffer_Occupancy(Frames_Removed,:) = [];
        %Add bytes send OLT to ONU to total bytes transmitted
        Total_Bytes_Sent = Total_Bytes_Sent + Bytes_to_Send;
        %Calculate new size of OLT's Buffer
        Buffer_Size(1,1) = Buffer_Size(1,1) - Bytes_to_Send; 
        %Hold bytes OLT ask from ONU to send back
        Bandwidth_Distribution = 0;
        %If ONU has nothing to send 
        if Bytes_ONU_Asks(ONU_ID,1) == 0 
            %Hold flag no frames to send
            Flag_Only_Report = 1;
            %Send bytes_to_send and give minimum Rm Bandwidth 
            %Hold bandwidth distribution (Report message size count in total Rm Bytes)
            Bandwidth_Distribution = Rm;
            %Calculate Remaining_Bandwidth 2,5Gbps - Rm (Minimum Bytes)
            Remaining_Bandwidth = (2.5/8)*10^9 - Rm; %Bytes
                
        else %If ONU has bytes to send
            Flag_Only_Report = 0;
            %Calculate Remaining_Bandwidth 
            %Holds (N-ONU_ID) * Rm Bytes for the remaining ONUs
            Remaining_Bandwidth = Remaining_Bandwidth - (N - ONU_ID)*Rm; %Bytes
            %Count Report message size 64Bytes
            Remaining_Bandwidth = Remaining_Bandwidth - Report_msg_Size;
            %Search all frames in buffer 
            for frames = 1:size(ONU_Buffer_Occupancy,1)
                %Find frames from that specific ONU
                if ONU_Buffer_Occupancy(frames,3) == ONU_ID
                    %If Total bytes ONU asks to send is greater than zero
                    if Bytes_ONU_Asks(ONU_ID,1) > 0
                        %If that frame can fit to remaining bandwidth
                        if Bandwidth_Distribution + ONU_Buffer_Occupancy(frames,2) <= Remaining_Bandwidth
                            %Increase total Bandwidth_Distribution
                            Bandwidth_Distribution = Bandwidth_Distribution + ONU_Buffer_Occupancy(frames,2);
                            %Remove size of that frame from total bytes ONU has asked to send
                            Bytes_ONU_Asks(ONU_ID,1) = Bytes_ONU_Asks(ONU_ID,1) - ONU_Buffer_Occupancy(frames,2);
                            %Calculate the new remaining bandwidth
                            Remaining_Bandwidth = Remaining_Bandwidth - ONU_Buffer_Occupancy(frames,2);
                        else
                            break;
                        end
                    else
                        break;
                    end
                end
            end
            %Calculate Remaining_Bandwidth 
            %Give (N-ONU_ID) * Rm Bytes for the remaining ONUs back to Total Bandwidth
            Remaining_Bandwidth = Remaining_Bandwidth + (N - ONU_ID)*Rm; %Bytes
        end
        %Start Transmission Time is : Time + RTT/2 of Distance of this ONU from OLT + bytes OLT has
        %for this ONU + fixed BWmap size  * 8 to calculated as bits / 10GBps(Downstream)
        %Calculate start and ending time of transmission of report message from this ONU
        start_transmission_time = Time + RTT_2(1,ONU_ID) + ((Bytes_to_Send + BWmap_Size)*8)/(10*10^9);            
        while true
            %Ending Time is: start time + RTT/2 + bytes of report message ONU will send + Minimum Bandwidth * 8 / 2.5GBps(Upstream)
            ending_time = start_transmission_time + + RTT_2(1,ONU_ID) + Bandwidth_Distribution*8/2.5*10^9;
            if find(Ending_Times_of_Transmissions(1,:) == ending_time)
                %Check if any other frame will be arrived at the same time and
                %add a guard time to prevent it
                start_transmission_time = start_transmission_time + Guard_Time;
            else
                break;
            end
        end  
        %Holds ending time of this transmission
        Ending_Times_of_Transmissions(1,ONU_ID) = ending_time;

        %Call Event 4 of ONU			
        Event_List(1,end+1) = 4; 
        Event_List(2,end) = start_transmission_time; %seconds
        Event_List(3,end) = 3;%Third priority 
        Event_List(4,end) = ONU_ID;%ONU_ID 
        if Flag_Only_Report == 1
            Event_List(5,end) = 0; %Ask zero bytes from ONU to transmit except ONU_Buffer_Occupancy Report (64Bytes) // OLT gives minimum Rm Bandwidth
        else
            Event_List(5,end) = Bandwidth_Distribution; %Total Bandwidth that OLT gives to that ONU
        end
    end
    %Event3 call itself after 125μ seconds
    Event_List(1,end+1) = 3;
    Event_List(2,end) = Time + 125*10^(-6);
    Event_List(3,end) = 1; %First priority frame
end
%Event 4: Remove frames OLT asks to send from buffer and send new report message (refresh Bytes_ONU_Asks array)
function [ Event_List, ONU_Buffer_Occupancy, Bytes_ONU_Asks, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size ] = Event4 ( Time, Event_List, ONU_Buffer_Occupancy, Bytes_ONU_Asks, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent, Buffer_Size)

   %Read BWmap message from event list
   ONU_ID = Event_List(4,1);
   total_bytes_to_send = Event_List(5,1);
   Total_Bytes = Event_List(5,1);
   sprintf('Event4: ONU %d read BWmap at Time %d -//- Distribution Bandwidth: %d -//- Start transmission', ONU_ID, Time, Total_Bytes)
   %Remove frames from the bottom of the Buffer 
   %Search all frames in buffer 
   %Holds index of frames will be send
   Frames_Sended = zeros(0,1);
   
   for frames = 1:size(ONU_Buffer_Occupancy,1)
        %Find frames from that specific ONU
        if ONU_Buffer_Occupancy(frames,3) == ONU_ID
            %If Total bytes OLT asks to send is greater than zero
            if Total_Bytes > 0
                %If that frame bytes are less or equal to total bytes to send and is not transmitted yet
                %hold index of that frame
                if ONU_Buffer_Occupancy(frames,2) <= Total_Bytes && ONU_Buffer_Occupancy(frames,4) == 0
                    %Refresh total bytes to send
                    Total_Bytes = Total_Bytes - ONU_Buffer_Occupancy(frames,2);
					%Hold frame row
                    Frames_Sended(end+1,1) = frames;
					%flag that frame as transmitted
                    ONU_Buffer_Occupancy(frames,4) = 1;
                    %Calculate waiting time for this frame Time (now ) - Time of insertion in ONUs buffer
                    Total_Waiting_Time = Total_Waiting_Time + (Time - ONU_Buffer_Occupancy(frames,1));
                    Total_Frames_Sent = Total_Frames_Sent + 1;
                else
                    break;
                end
            else
                break;
            end

       end
   end
   %Add total bytes sent ONU to OLT
   Total_Bytes_Sent = Total_Bytes_Sent + total_bytes_to_send;
   %Remove all frames sent
   ONU_Buffer_Occupancy(Frames_Sended,:) = [];
   %Refresh buffer size of this ONU
   Buffer_Size(ONU_ID,1) = Buffer_Size(ONU_ID,1) - total_bytes_to_send;
   %Renew buffer of frames that ONU asks
   Bytes_ONU_Asks(ONU_ID,1) = 0;
   %Calculate total bytes of all frames that ONU has now in buffer 
   for frames = 1:size(ONU_Buffer_Occupancy,1)
       if ONU_Buffer_Occupancy(frames,3) == ONU_ID
           Bytes_ONU_Asks(ONU_ID,1) = Bytes_ONU_Asks(ONU_ID,1) + ONU_Buffer_Occupancy(frames,2);
       end
   end
end
%Event5: Simulation End // Calculate Network Statistics 
function [  Sim_Flag, Throughput, Mean_Frame_Delay ] = Event5 ( Time, Total_Bytes_Sent, Total_Waiting_Time, Total_Frames_Sent )
    sprintf('Simulation end at Sim-Time %d', Time)
    toc
    Sim_Flag = false; 
    %Calculate Throughput Total bytes Sent * 8 / Time 
    Throughput = (( Total_Bytes_Sent *  8 )/ Time)/10^9; %Gbps
    sprintf('Network Throughput is: %.2f GBps',Throughput)
    %Calculate Mean Frame Delay
    Mean_Frame_Delay = (Total_Waiting_Time / Total_Frames_Sent);
    sprintf('Mean Frame Delay is: %f seconds',Mean_Frame_Delay) %seconds
end
