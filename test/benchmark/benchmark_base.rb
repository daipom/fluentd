require_relative '../helper'

require 'fileutils'
require 'timeout'
require 'securerandom'
require 'net/http'
require 'fluent/file_wrapper'

class BenchmarkBase < ::Test::Unit::TestCase
  SUPERVISOR_PID_PATTERN = /starting fluentd-[.0-9]+ pid=(\d+)/
  WORKER_PID_PATTERN = /starting fluentd worker pid=(\d+) /

  def tmp_dir
    File.join(File.dirname(__FILE__), "..", "tmp", "benchmark", "tail" "fluentd#{ENV['TEST_ENV_NUMBER']}", SecureRandom.hex(10))
  end

  def setup
    @tmp_dir = tmp_dir
    FileUtils.mkdir_p(@tmp_dir)
    @supervisor_pid = nil
    @worker_pid = nil
    @worker_started = false
    @metrics = []
    @worker_rss_data = []
    ENV["TEST_RUBY_PATH"] = nil
  end

  def teardown
    begin
      FileUtils.rm_rf(@tmp_dir)
    rescue Errno::EACCES
      # It may occur on Windows because of delete pending state due to delayed GC.
      # Ruby 3.2 or later doesn't ignore Errno::EACCES:
      # https://github.com/ruby/ruby/commit/983115cf3c8f75b1afbe3274f02c1529e1ce3a81
    end
  end

  def metrics_data(plugin_id, metrics_name)
    @metrics.map do |m|
      # [{"plugins"=>[{}, {}, ...]}, {}, ,,,]
      m["plugins"]
    end.map do |m|
      # [[{}, {}, ...], [], ,,,]
      m.filter do |mm|
        mm["plugin_id"] == plugin_id
      end.first
    end.map do |m|
      # [{}, {}, ,,,]
      m[metrics_name]
    end
  end

  def process_exist?(pid)
    begin
      r = Process.waitpid(pid, Process::WNOHANG)
      return true if r.nil?
      false
    rescue SystemCallError
      false
    end
  end

  def create_conf_file(name, content, ext_enc = 'utf-8')
    conf_path = File.join(@tmp_dir, name)
    Fluent::FileWrapper.open(conf_path, "w:#{ext_enc}:utf-8") do |file|
      file.write <<~CONF
        <source>
          @type monitor_agent
        </source>
      CONF
      file.write content
    end
    conf_path
  end

  def create_plugin_file(name, content)
    file_path = File.join(@tmp_dir, 'plugin', name)
    FileUtils.mkdir_p(File.dirname(file_path))
    Fluent::FileWrapper.open(file_path, 'w') do |file|
      file.write content
    end
    file_path
  end

  def create_cmdline(conf_path, *fluentd_options)
    if Fluent.windows?
      cmd_path = File.expand_path(File.dirname(__FILE__) + "../../../bin/fluentd")
      ["bundle", "exec", ServerEngine.ruby_bin_path, cmd_path, "-c", conf_path, *fluentd_options]
    else
      cmd_path = File.expand_path(File.dirname(__FILE__) + "../../../bin/fluentd")
      ["bundle", "exec", cmd_path, "-c", conf_path, *fluentd_options]
    end
  end

  def process_kill(pid)
    if Fluent.windows?
      Process.kill(:KILL, pid) rescue nil
      return
    end

    begin
      Process.kill(:TERM, pid) rescue nil
      Timeout.timeout(10){ sleep 0.1 while process_exist?(pid) }
    rescue Timeout::Error
      Process.kill(:KILL, pid) rescue nil
    end
  end

  def execute_command(cmdline, chdir=@tmp_dir, env = {})
    null_stream = Fluent::FileWrapper.open(File::NULL, 'w')
    gemfile_path = File.expand_path(File.dirname(__FILE__) + "../../../Gemfile")

    env = { "BUNDLE_GEMFILE" => gemfile_path }.merge(env)
    cmdname = cmdline.shift
    arg0 = "testing-fluentd"
    IO.popen(env, [[cmdname, arg0], *cmdline], chdir: chdir, err: [:child, :out]) do |io|
      pid = io.pid
      begin
        yield pid, io
      ensure
        process_kill(pid)
        process_kill(@supervisor_pid) if @supervisor_pid
        process_kill(@worker_pid) if @worker_pid
        Timeout.timeout(10) { sleep 0.1 while process_exist?(pid) }
      end
    end
  ensure
    null_stream.close rescue nil
  end

  def eager_read(io)
    buf = +''

    loop do
      b = io.read_nonblock(1024, nil, exception: false)
      if b == :wait_readable || b.nil?
        return buf
      end
      buf << b
    end
  end

  def run_fluentd(cmdline, timeout: 300, env: {})
    stdio_buf = ""
    execute_command(cmdline, @tmp_dir, env) do |pid, stdout|
      begin
        waiting(timeout) do
          while process_exist?(pid)
            readables, _, _ = IO.select([stdout], nil, nil, 1)
            if readables
              stdio_buf << eager_read(readables.first)
            end

            if @worker_started
              monitor
              if block_given?
                break if yield
              end
            else
              check(stdio_buf)
            end
          end
        end
      rescue Timeout::Error
        raise if block_given?
      ensure
        stdio_buf.split("\n").each do |log|
          p log
        end
      end
    end
  end

  def check(log)
    unless @supervisor_pid
      if SUPERVISOR_PID_PATTERN =~ log
        @supervisor_pid = $1.to_i
      end
    end
    unless @worker_pid
      if WORKER_PID_PATTERN =~ log
        @worker_pid = $1.to_i
      end
    end
    unless @worker_started
      if log.include?("fluentd worker is now running")
        @worker_started = true
      end
    end
  end

  def monitor
    @metrics << metrics
    @worker_rss_data << rss(@worker_pid)
  end

  def metrics
    response = Net::HTTP.get(URI.parse("http://localhost:24220/api/plugins.json"))
    JSON.parse(response)
  end

  def rss(pid)
    if Fluent.windows?
      rss_win(pid)
    else
      rss_unix(pid)
    end
  end

  def rss_unix(pid)
    `ps -o rss= -p #{pid}`.strip.to_i
  end

  def rss_win(pid)
    # TODO
  end
end
