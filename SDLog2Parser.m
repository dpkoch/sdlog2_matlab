classdef SDLog2Parser < handle
    %SDLOG2PARSER Class for parsing PX4 sdlog2 log files
    %   This class is an adaptation of the sdlog2 parsing script found at
    %   https://github.com/PX4/Firmware/blob/master/Tools/sdlog2/sdlog2_dump.py
    %
    %   Example:
    %       
    %       % parse a log file 'log001.px4log' in the current directory.
    %       parser = SDLog2Parser;
    %       parser.process('log001.px4log');
    
    properties
        BLOCK_SIZE = 8192
        MSG_HEADER_LEN = 3
        MSG_HEAD1 = hex2dec('A3')
        MSG_HEAD2 = hex2dec('95')
        MSG_FORMAT_PACKET_LEN = 89
        MSG_FORMAT_STRUCT = 'BBnNZ'
        MSG_TYPE_FORMAT = hex2dec('80')
        
        time_msg = '';
        correct_errors = false;
        
        msg_descrs
        msg_names
        msg_labels
        
        buffer
        ptr
        
        formats
        
        last_time
        log
    end
    
    methods
        
        function self = SDLog2Parser
            self.formats = containers.Map;
            self.formats('b') = struct('class', 'int8',   'length', 1,  'mult', []);
            self.formats('B') = struct('class', 'uint8',  'length', 1,  'mult', []);
            self.formats('h') = struct('class', 'int16',  'length', 2,  'mult', []);
            self.formats('H') = struct('class', 'uint16', 'length', 2,  'mult', []);
            self.formats('i') = struct('class', 'int32',  'length', 4,  'mult', []);
            self.formats('I') = struct('class', 'uint32', 'length', 4,  'mult', []);
            self.formats('f') = struct('class', 'single', 'length', 4,  'mult', []);
            self.formats('n') = struct('class', 'char',   'length', 4,  'mult', []);
            self.formats('N') = struct('class', 'char',   'length', 16, 'mult', []);
            self.formats('Z') = struct('class', 'char',   'length', 64, 'mult', []);
            self.formats('c') = struct('class', 'int16',  'length', 2,  'mult', 0.01);
            self.formats('C') = struct('class', 'uint16', 'length', 2,  'mult', 0.01);
            self.formats('e') = struct('class', 'int32',  'length', 4,  'mult', 0.01);
            self.formats('E') = struct('class', 'uint32', 'length', 4,  'mult', 0.01);
            self.formats('L') = struct('class', 'int32',  'length', 4,  'mult', 0.0000001);
            self.formats('M') = struct('class', 'uint8',  'length', 1,  'mult', []);
            self.formats('q') = struct('class', 'int64',  'length', 8,  'mult', []);
            self.formats('Q') = struct('class', 'uint64', 'length', 8,  'mult', []);
        end
        
        function reset(self)
            self.msg_descrs = struct(...
                'length', [],...
                'name', cell(1,255),...
                'format', cell(1,255),...
                'labels', cell(1,255));
            self.msg_names = cell(1,0);
            self.msg_labels = cell(1,0);
            
            self.buffer = zeros(1,0,'uint8');
            self.ptr = 1;
            
            self.last_time = [];
            self.log = struct;
        end
        
        function setTimeMsg(self, time_msg)
            self.time_msg = time_msg;
        end
        
        function log = process(self, fn)
            self.reset()
            
            f = fopen(fn, 'r');
            if f < 0
                error('Could not open file ''%s''', fn)
            end
            
            bytes_read = 0;
            while true
                chunk = fread(f, [1,self.BLOCK_SIZE], '*uint8');
                if isempty(chunk)
                    break
                end
                
                self.buffer = [self.buffer(self.ptr:end) chunk];
                self.ptr = 1;
                clear chunk
                
                while self.bytesLeft() >= self.MSG_HEADER_LEN
                    head1 = self.buffer(self.ptr);
                    head2 = self.buffer(self.ptr+1);
                    if head1 ~= self.MSG_HEAD1 || head2 ~= self.MSG_HEAD2
                        if self.correct_errors
                            self.ptr = self.ptr + 1;
                            continue
                        else
                            error('Invalid header at %1$i (0x%1$X): %2$02X %3$02X, must be %4$02X %5$02X',...
                                bytes_read + self.ptr, head1, head2, self.MSG_HEAD1, self.MSG_HEAD2)
                        end
                    end
                    
                    msg_type = self.buffer(self.ptr+2);
                    if msg_type == self.MSG_TYPE_FORMAT
                        if self.bytesLeft() < self.MSG_FORMAT_PACKET_LEN
                            break
                        else
                            self.parseMsgDescr()
                        end
                    else
                        msg_descr = self.msg_descrs(msg_type+1);
                        if isempty(msg_descr.name)
                            error('Unknown msg type: %i', msg_type)
                        end
                        if self.bytesLeft() < msg_descr.length
                            break
                        end
                        self.parseMsg(msg_descr)
                    end
                end
                bytes_read = bytes_read + self.ptr;
                
            end
            
            fclose(f);
            log = self.log;
        end
        
        function bytes = bytesLeft(self)
            bytes = length(self.buffer) - (self.ptr-1);
        end
        
        function parseMsgDescr(self)
            data = self.unpack(self.MSG_FORMAT_STRUCT, self.buffer(self.ptr+self.MSG_HEADER_LEN : self.ptr+self.MSG_FORMAT_PACKET_LEN-1));
            msg_type = uint16(data{1});
            if msg_type ~= self.MSG_TYPE_FORMAT;
                msg_length = double(data{2});
                msg_name = data{3};
                msg_format = data{4};
                msg_label = strsplit(data{5}, ',');
                
                self.msg_descrs(msg_type+1).length = msg_length;
                self.msg_descrs(msg_type+1).name = msg_name;
                self.msg_descrs(msg_type+1).format = msg_format;
                self.msg_descrs(msg_type+1).labels = msg_label;
                
                self.msg_names{end+1} = msg_name;
                self.msg_labels{end+1} = msg_label;
            end
            self.ptr = self.ptr + self.MSG_FORMAT_PACKET_LEN;
        end
        
        function parseMsg(self, msg_descr)
            data = self.unpack(msg_descr.format, self.buffer(self.ptr+self.MSG_HEADER_LEN : self.ptr+msg_descr.length-1));
            % initialize message struct
            if ~isfield(self.log, msg_descr.name)
                for i=1:length(data)
                    if strcmp(self.formats(msg_descr.format(i)).class, 'char')
                        self.log.(msg_descr.name).(msg_descr.labels{i}) = {};
                    else
                        self.log.(msg_descr.name).(msg_descr.labels{i}) = []; % convert all numeric types to double
                    end
                end
                if ~isempty(self.time_msg) && ~strcmp(msg_descr.name, self.time_msg) && ~isempty(self.last_time)
                    self.log.(msg_descr.name).([self.time_msg '__']) = [];
                end
            end
            % store data
            for i=1:length(data)
                if strcmp(self.formats(msg_descr.format(i)).class, 'char')
                    self.log.(msg_descr.name).(msg_descr.labels{i}){end+1,1} = data{i};
                else
                    self.log.(msg_descr.name).(msg_descr.labels{i})(end+1,1) = data{i};
                end
            end
            % handle time messages
            if ~isempty(self.time_msg) && strcmp(msg_descr.name, self.time_msg)
                self.last_time = data{1};
            else
                if isfield(self.log.(msg_descr.name), [self.time_msg '__'])
                    self.log.(msg_descr.name).([self.time_msg '__'])(end+1,1) = self.last_time;
                end
            end
            
            self.ptr = self.ptr + msg_descr.length;
        end
        
        function result = unpack(self, format, msg)
            result = cell(1,length(format));
            index = 1;
            for i=1:length(format)
                class = self.formats(format(i)).class;
                len = self.formats(format(i)).length;
                mult = self.formats(format(i)).mult;
                
                if strcmp(class, 'char') % strings
                    result{i} = deblank(char(msg(index:index+len-1)));
                else % numbers
                    %TODO check endian-ness
                    raw = typecast(msg(index:index+len-1), class);
                    if ~isempty(mult)
                        result{i} = single(raw)*mult;
                    else
                        result{i} = raw;
                    end
                end
                
                index = index + len;
            end
        end
        
    end
    
end

