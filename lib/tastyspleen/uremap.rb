#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'


module TastySpleen

  class URemap
    URemapArgs = Struct.new(:uremap, :gremap)
  
    class URemapArgParser
      URemapArgs = TastySpleen::URemap::URemapArgs
      ParseState = Struct.new(:data, :arg_files_parsed)
      
      def parse_switches(argv)
        st = ParseState.new(URemapArgs.new({}, {}), {})
        buf = argv.join("\n")
        parse_argbuf(st, buf)
        st.data
      end

      def partition_switches_and_args(argv)
        found_non_switch = false
        args, switches = argv.partition do |arg|
          if found_non_switch
            true
          elsif arg == "--"
            found_non_switch = true
            false
          elsif arg[0] != "-"
            found_non_switch = true
          end
        end
        switches.delete_if {|sw| sw == "--"}
        [switches, args]
      end
      
      protected
      
      def parse_argbuf(st, buf)
        buf.each_line do |line|
          line.chomp!
          next if line.strip.empty?
          parse_arg(st, line)
        end
      end
      
      def parse_arg(st, line)
        if line =~ /\A\s*-u(\d+):(\d+)\s*\z/
          from_uid, to_uid = $1.to_i, $2.to_i
          ((from_uid < 0) || (to_uid < 0)) and raise("FATAL: negative uid")
          ((from_uid.zero?) || (to_uid.zero?)) and raise("FATAL: won't remap root user")
          (st.data.uremap.key?(from_uid)) and raise("FATAL: duplicate remap uid: #{from_uid.inspect}")
          st.data.uremap[from_uid] = to_uid
        elsif line =~ /\A\s*-g(\d+):(\d+)\s*\z/
          from_gid, to_gid = $1.to_i, $2.to_i
          ((from_gid < 0) || (to_gid < 0)) and raise("FATAL: negative gid")
          ((from_gid.zero?) || (to_gid.zero?)) and raise("FATAL: won't remap root group")
          (st.data.gremap.key?(from_gid)) and raise("FATAL: duplicate remap gid: #{from_gid.inspect}")
          st.data.gremap[from_gid] = to_gid        
        elsif line =~ /\A\s*-f(.*)\z/
          path = $1
          (path.empty?) and raise("FATAL: missing path to -f argument")
          (test(?f, path)) or raise("FATAL: argfile not found: #{path.inspect}")
          parse_argfile(st, path)
        else
          raise("FATAL: unrecognized argument: #{line.inspect}")
        end
      end
      
      def parse_argfile(st, path)
        if st.arg_files_parsed.key?(path)
          warn "WARN: skipping already-parsed argfile: #{path.inspect}"
          return
        end
        
        st.arg_files_parsed[path] = true
        buf = File.read(path)
        parse_argbuf(st, buf)
      end
    end # URemapArgParser
  
    def initialize
      @uremap = {}
      @gremap = {}
    end
    
    def parse_args(argv=ARGV)
      parser = URemapArgParser.new
      switches, args = parser.partition_switches_and_args(argv)
warn "switches=#{switches.inspect}"
warn "args=#{args.inspect}"
      data = parser.parse_switches(switches)
      @uremap = data.uremap
      @gremap = data.gremap
warn "uremap=#{@uremap.inspect}"
warn "gremap=#{@gremap.inspect}"
    end
    
    protected
    
    def is_uid_remap?
    end
    
    
  # Find.find(root) do |path|
  #   begin
  #     if test(?f, path) && looks_like_cache_key?(path)
  #       # @logger.dbg("#{self.class.name}: purging cache file #{path.inspect}")
  #       File.unlink(path)
  #     end
  #   rescue SignalException, SystemExit => ex
  #     raise
  #   rescue Exception => ex
  #     @logger.warn("#{self.class.name}.#{__method__}: exception: #{ex.message}")
  #   end
  # end
    
    
  end # URemap

end # TastySpleen


if $0 == __FILE__
  uremap = TastySpleen::URemap.new
  uremap.parse_args(ARGV)
end
