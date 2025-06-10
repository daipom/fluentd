require_relative 'benchmark_base'

class BenchmarkTail < BenchmarkBase
  def prepare_input_logfile(path, line_counts)
    line = { "message": "a" * 1024 }.to_json
    File.open(path, "w") do |f|
      line_counts.times do
        f.puts line
      end
    end
  end

  def last_emit_records(plugin_id)
    data = metrics_data(plugin_id, "emit_records")
    return 0 if data.empty?

    data.last
  end

  def test_throughput
    plugin_id = "target"
    input_filepath = File.join(@tmp_dir, "input.log")
    line_counts = 10_000_000

    puts "start making input logfile..."
    prepare_input_logfile(input_filepath, line_counts)
    puts "finish making input logfile."

    # Need "skip_refresh_on_startup" to complete entire Fluentd starting process before starting tail.
    # So, we have to wait the first "refresh_watcher".
    # Thus, we need to set short "refresh_interval".
    conf_path = create_conf_file('test.conf', <<~CONF)
      <source>
        @type tail
        @id #{plugin_id}
        tag test
        path #{input_filepath}
        refresh_interval 3s
        read_from_head
        skip_refresh_on_startup
        <parse>
          @type json
        </parse>
      </source>
      <match test>
        @type null
        <buffer>
          chunk_limit_size 1M
        </buffer>
      </match>
    CONF
    assert File.exist?(conf_path)

    run_fluentd(create_cmdline(conf_path)) do
      last_emit_records = last_emit_records(plugin_id)
      p "emit_records: #{last_emit_records}"
      p "RSS(KB): #{@worker_rss_data.last}"
      last_emit_records == line_counts
    end

    # limit to data after the tail starts
    emit_records_data = metrics_data(plugin_id, "emit_records").reject { |v| v == 0 }
    # exclude edge data
    excluded_egde = emit_records_data[1..-2]
    throughput = (excluded_egde[-1] - excluded_egde[0]) / excluded_egde.length

    p "------------------------"
    p "throughput (record/sec): #{throughput}"
  end
end
