require 'rake'

module Orgmode
  class BabelOutputBuffer < OutputBuffer
    attr_reader :tangle
    attr_reader :scripts
    attr_reader :in_buffer_settings

    def initialize(output, opts={})
      super(output)

      @in_buffer_settings = opts[:in_buffer_settings]

      # ~@tangle~ files are put in the right path
      # : @tangle['/path'] = [Lines]
      @tangle  = Hash.new {|h,k| h[k] = {
          :lines  => '',
          :header => {},
          :lang   => ''
        }
      }

      # ~@scripts~ are tangled in order and ran
      # : @scripts = [text, text, ...]
      @scripts = Hash.new {|h,k| h[k] = {
          :lines   => '',
          :header  => {},
          :lang    => ''
        }
      }
      @scripts_counter = 0
      @buffer = ''
    end

    def push_mode(mode, indent)
      super(mode, indent)
    end

    def pop_mode(mode = nil)
      m = super(mode)
      @list_indent_stack.pop
      m
    end

    def insert(line)
      # We try to get the lang from #+BEGIN_SRC and #+BEGIN_EXAMPLE blocks
      if line.begin_block?
        case
        when line.block_header_arguments[':tangle']
          @current_tangle = line.block_header_arguments[':tangle']
          @tangle[@current_tangle][:header] = {
            :shebang => line.block_header_arguments[':shebang'],
            :mkdirp  => line.block_header_arguments[':mkdirp']
          }
          @tangle[@current_tangle][:lang] = line.block_lang
        when line.properties['block_name']
          # unnamed blocks are not run
          @current_tangle = nil
          @buffer = ''

          # Need to keep track of the options from a block before running it
          @scripts[@scripts_counter][:header] = { 
            :shebang => line.block_header_arguments[':shebang'],
            :mkdirp  => line.block_header_arguments[':mkdirp'],
            :name    => line.properties['block_name'],
            :before  => line.block_header_arguments[':before'],
            :after   => line.block_header_arguments[':after'],
            :procs   => line.block_header_arguments[':procs'],
          }
          @scripts[@scripts_counter][:lang] = line.block_lang
        # TODO: have a way to specify which are the default binaries to be used per language
        # when binary_detected?(@block_lang)
        else
          # reset tangling
          @current_tangle = nil
          @buffer = ''
        end
      end

      case
      when (line.start_of_results_code_block?)
        @accumulate_results_block = true
      when (line.assigned_paragraph_type == :code and @current_tangle)
        # Need to keep track of the current tangle to buffer its lines
        @tangle[@current_tangle][:lines] << line.output_text << "\n"
      when (line.assigned_paragraph_type == :code  or \
            line.paragraph_type == :inline_example)
        # When a tangle is not going on, it means that the lines would go
        # into a runnable script
        @buffer << line.output_text << "\n"
      when (!@buffer.empty? and not (line.begin_block? or \
                                     line.assigned_paragraph_type == :code))
        # Fix indentation and remove fix commas from Org mode before flushing
        strip_code_block!
        if @accumulate_results_block
          @scripts[@scripts_counter - 1][:results] = @buffer
          @accumulate_results_block = false
        else
          @scripts[@scripts_counter][:lines] << @buffer
        end
        @buffer = ''
        @scripts_counter += 1
      end

      @output_type = line.assigned_paragraph_type || line.paragraph_type
    end

    # Flushing is a bit different since we still need the metadata
    # from lines in order to flush to correct tangle buffer
    # TODO: Should be in the parent class as well...
    def flush!; false; end

    # TODO: This should be in the parent class....
    def output_footnotes!; false; end

    # TODO: This should be part of some utils package from OrgRuby
    def strip_code_block!
      if @code_block_indent and @code_block_indent > 0
        strip_regexp = Regexp.new("^" + " " * @code_block_indent)
        @buffer.gsub!(strip_regexp, "")
      end
      @code_block_indent = nil

      # Strip proctective commas generated by Org mode (C-c ')
      @buffer.gsub! /^(\s*)(,)(\s*)([*]|#\+)/ do |match|
        "#{$1}#{$3}#{$4}"
      end
    end
  end
end
