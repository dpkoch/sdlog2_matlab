function log = sdlog2matlab(filename, varargin)
%SDLOG2MATLAB Parse PX4 binary log file
%   SDLOG2MATLAB(FILENAME) returns the parsed log data as a structure.
%   
%   The FILENAME can be argument can be followed by parameter/value pairs
%   to specify the following additional options:
%   
%   Parameter   Default     Description
%   =========   =======     ======
%   timeMsg     'TIME'      Name of the time message for the log file.
%                           Specifying the empty string '' disables
%                           indexing by time.

% parse function inputs
p = inputParser;
p.FunctionName = 'sdlog2matlab';
p.CaseSensitive = false;
p.KeepUnmatched = false;
p.PartialMatching = true;
p.StructExpand = true;

p.addRequired('filename', @ischar)
p.addParameter('timeMsg', 'TIME', @ischar)

p.parse(filename, varargin{:})

if ~exist(p.Results.filename, 'file')
    error('The file ''%s'' does not exist', p.Results.filename)
end

% process log file
if verLessThan('matlab', '8.4') % python only supported since R2014b
    warning('Python only supported since R2014b (Version 8.4); falling back to MATLAB parser. This will work, but may take up to several minutes.')
    parser = SDLog2Parser;
    parser.setTimeMsg(p.Results.timeMsg);
    log = parser.process(p.Results.filename);
else
    % add current folder to python search path
    if count(py.sys.path,'') == 0
        insert(py.sys.path,int32(0),'');
    end
    
    pylog = py.sdlog2.parseLog(py.str(p.Results.filename), py.str(p.Results.timeMsg));
    log = python2matlab(pylog);
end

log = normalizetime(log, [p.Results.timeMsg '__'], [lower(p.Results.timeMsg) '__']);

end

function matlab = python2matlab(python)
%PYTHON2MATLAB Recursively convert python data types to matlab data types
    switch class(python)
        case class(py.dict)
            matlab = struct(python);
            names = fieldnames(matlab);
            for i=1:length(names)
                matlab.(names{i}) = python2matlab(matlab.(names{i}));
            end
        case class(py.list)
            raw = cell(python);
            try
                matlab = cellfun(@double, raw).';
            catch
                matlab = cellfun(@char, raw, 'UniformOutput', false).';
            end
        case class(py.str)
            matlab = char(python);
        otherwise
            error('Encountered unsupported python type ''%s''', class(python))
    end
end

function log = normalizetime(log, raw_name, norm_name)
%NORMALIZETIME Remove time offset and convert to seconds
    starttime = log.TIME.StartTime(1);
    names = fieldnames(log);
    for i=1:length(names)
        if isfield(log.(names{i}), raw_name)
            log.(names{i}).(norm_name) = (log.(names{i}).(raw_name) - starttime) / 1e6;
        end
    end
end
