#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'
require 'find'


module TastySpleen

  class URemap
    URemapArgs = Struct.new(:uremap, :gremap, :dry_run, :verbose)
  
    class URemapArgParser
      URemapArgs = TastySpleen::URemap::URemapArgs
      ParseState = Struct.new(:data, :arg_files_parsed)
      
      def parse_switches(argv)
        st = ParseState.new(URemapArgs.new({}, {}, false, false), {})
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
        elsif line =~ /\A\s*--dry-run\s*\z/
          st.data.dry_run = true
        elsif line =~ /\A\s*--verbose\s*\z/
          st.data.verbose = true
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
      @paths = []
      @dry_run = false
      @verbose = false
    end
    
    def parse_args(argv=ARGV)
      parser = URemapArgParser.new
      switches, args = parser.partition_switches_and_args(argv)
# warn "switches=#{switches.inspect}"
# warn "args=#{args.inspect}"
      @paths = args
      data = parser.parse_switches(switches)
      @uremap = data.uremap
      @gremap = data.gremap
      @dry_run = data.dry_run
      @verbose = data.verbose
warn "uremap=#{@uremap.inspect}"
warn "gremap=#{@gremap.inspect}"
# warn "dry_run=#{@dry_run.inspect}"
# warn "verbose=#{@verbose.inspect}"
    end
    
    def preflight
      (@paths.empty?) and raise("FATAL: no path arguments supplied")
      (@uremap.empty? && @gremap.empty?) and raise("FATAL: nothing to do (no uremaps or gremaps supplied)")
      @paths.each {|path| (test(?d, path)) or raise("FATAL: path not found: #{path.inspect}")}
    end
    
    def uremap_path_trees(paths=@paths)
      Find.find(*paths) do |path|
        begin
          uremap_path(path)
        rescue SignalException, SystemExit => ex
          raise
        rescue Exception => ex
          warn("ERROR: #{ex.message}")
        end
      end
    end
    
    def uremap_path(path)
      st = File.lstat(path)
      new_uid, new_gid = nil, nil
      if (uid = st.uid) > 0
        if @uremap.key?(uid)
          new_uid = @uremap[uid]
        end
      end
      if (gid = st.gid) > 0
        if @gremap.key?(gid)
          new_gid = @gremap[gid]
        end
      end
      if new_uid || new_gid
        if st.file? && (st.setuid? || st.setgid?)
          warn("WARN: changing setuid/setgid file: #{path.inspect} - (u#{uid}=>#{new_uid||uid}, g#{gid}=>#{new_gid||gid}, mode=#{st.mode.to_s(8)})")
        end
        if @verbose
          ustr = (new_uid) ? "u#{uid}=>#{new_uid}" : "(u#{uid})"
          gstr = (new_gid) ? "g#{gid}=>#{new_gid}" : "(g#{gid})"
          puts("#{ustr}\t#{gstr}\t#{path}")
        end
        unless @dry_run
          File.lchown(new_uid, new_gid, path)
          File.chmod(st.mode, path)  # ruby's lchown seems to have some nanny behavior and clears setuid/setgid bits, so restore the original mode
        end
      end
    end
    
  end # URemap

end # TastySpleen


if $0 == __FILE__
  begin
    uremap = TastySpleen::URemap.new
    uremap.parse_args(ARGV)
    uremap.preflight
    uremap.uremap_path_trees
  rescue Exception => ex
    warn("ERROR: #{ex.message}")
  end
end
