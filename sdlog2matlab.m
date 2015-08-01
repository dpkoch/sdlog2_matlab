function log = sdlog2matlab(filename, direction)
%SDLOG2MATLAB Parse PX4 binary log file
%   SDLOG2MATLAB(FILENAME) returns the parsed log data as a structure.
%   SDLOG2MATLAB(FILENAME,DIR) allows you to specify whether the data is
%   returned as row (DIR='row') or column (DIR='col', the default) vectors.

if nargin < 2
    direction = 'col';
end

if verLessThan('matlab', '8.4') % python only supported since r2014b
    warning('Python only supported since R2014b (Version 8.4); falling back to MATLAB parser. This will work, but may take up to several minutes.')
    parser = SDLog2Parser;
    parser.setTimeMsg('TIME');
    log = parser.process(filename);
else
    % add current folder to python search path
    if count(py.sys.path,'') == 0
        insert(py.sys.path,int32(0),'');
    end
    
    pylog = py.sdlog2.parseLog(py.str(filename));
    log = python2matlab(pylog, direction);
end

log = normalizetime(log, 'TIME__', 'time__');

end

function matlab = python2matlab(python, direction)
%PYTHON2MATLAB Recursively convert python data types to matlab data types
    switch class(python)
        case class(py.dict)
            matlab = struct(python);
            names = fieldnames(matlab);
            for i=1:length(names)
                matlab.(names{i}) = python2matlab(matlab.(names{i}), direction);
            end
        case class(py.list)
            raw = cell(python);
            try
                matlab = cellfun(@double, raw);
            catch
                matlab = cellfun(@char, raw, 'UniformOutput', false);
            end
            if strcmp(direction, 'col')
                matlab = matlab.';
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
