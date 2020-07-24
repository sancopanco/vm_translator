module VMTranslator
  # Translate VM commands into Hack assembly code
  # Writes the assembly code that is the translation of given arithmetic, memory command
  class CodeWriter
    def initialize(output_filename)
      @output_file = File.new(output_filename, 'a')
      @current_line = nil
    end

    def write_arithmethic(command, line)
      @current_line = line
      translation = aritmetic_translation(command, line)
      @output_file.write(translation.join("\n"))
    end

    def write_push(command, segment, index, line)
      @current_line = line
      translation = translate_push(command, segment, index)
      @output_file.write(translation.join("\n"))
    end

    def write_pop(command, segment, index, line)
      @current_line = line
      translation = translate_pop(command, segment, index)
      @output_file.write(translation.join("\n"))
    end

    private

    #
    # Memory Access Commands
    #

    #
    # Memory Segments Mappping
    # Each segment is mapped direclty on the RAM, and its location is maintained
    # by keeping its physical base address in a dedicated register(LCL, ARG, THIS, THAT etc)
    # Segment[i] -> RAM[base + i]
    def segment_base_addr
      {
        local: 'LCL',
        argument: 'ARG',
        this: 'THIS',
        that: 'THAT',
        pointer: 3,
        temp: 5
      }
    end

    # push segment index: Push the value of segment[index] on the stack
    # addr = segment_base_addr + index, *SP = *addr, SP++
    # Current VM function's respective segment
    # SP points to the next topmost location in the stack
    def translate_push(command, segment, index)
      return translate_push_constant(command, segment, index) if segment == 'constant'
      [
        "\n// #{command} #{segment} #{index} --line: #{@current_line}",
        "@#{segment_base_addr[segment.to_sym]}",
        %w[pointer temp].include?(segment) ? 'D=A' : 'D=M',
        "@#{index}",
        'D=D+A', # D = RAM[LCL] + index -- addr = LCL + index
        'A=D',
        'D=M', # D = RAM[RAM[LCL] + index] -- *addr
        '@SP',
        'A=M', # A = RAM[SP]
        'M=D', # *SP = *addr
        '@SP',
        'M=M+1' # SP++
      ]
    end

    # pop segment index: Pop the top stack value and store it in segment[index]
    # addr = segment_base_addr + index, SP--, *addr = *SP
    def translate_pop(command, segment, index)
      [
        "\n// #{command} #{segment} #{index} --line: #{@current_line}",
        "@#{segment_base_addr[segment.to_sym]}",
        %w[pointer temp].include?(segment) ? 'D=A' : 'D=M',
        "@#{index}",
        'D=D+A', # D = segment_base_addr + index
        "@addr_#{@current_line}",
        'M=D', # addr_line = segment_base_addr + index
        '@SP',
        'M=M-1', # SP--
        'A=M',
        'D=M',
        "@addr_#{@current_line}",
        'A=M',
        'M=D' # *addr = *SP

      ]
    end

    def translate_push_constant(command, segment, value)
      [
        "\n// #{command} #{segment} #{value} --line: #{@current_line}",
        ## *SP = index
        "@#{value}", # A=index
        'D=A', # D=index,
        '@SP', # A=SP and RAM[SP] selected, M = RAM[SP]
        'A=M', # A=RAM[SP], A=*SP
        'M=D', # RAM[SP] = index, *SP = index
        ## SP++
        '@SP', # M=RAM[SP]
        'M=M+1' # RAM[SP] = RAM[SP] + 1
      ]
    end

    #
    # Stack Arithmetic
    #
    def aritmetic_translation(command, line)
      map = {
        add: :translate_arithmetic_add,
        sub: :translate_arithmetic_sub,
        eq: :translate_arithmetic_eq,
        lt: :translate_arithmetic_lt,
        gt: :translate_arithmetic_gt,
        neg: :translate_arithmetic_neg,
        and: :translate_logical_and,
        or: :translate_logical_or,
        not: :translate_logical_not
      }

      send(map[command.to_sym], command, line)
    end

    def translate_arithmetic_lt(_command, line)
      [
        "\n// lt ",
        'AM=M-1',
        'D=M',
        'A=A-1',
        'D=M-D',
        "@LT_#{line}",
        # false part
        'D;JLT',
        '@SP',
        'A=M-1',
        'M=0',
        "@END_#{line}",
        '0;JMP',
        "(LT_#{line})",
        # true part
        '@SP',
        'A=M-1',
        'M=-1',
        "(END_#{line})"
      ]
    end

    def translate_arithmetic_gt(_command, line)
      [
        "\n// gt ",
        'AM=M-1',
        'D=M',
        'A=A-1',
        'D=M-D',
        "@GT_#{line}",
        'D;JGT',
        # false part
        '@SP',
        'A=M-1',
        'M=0',
        "@END_#{line}",
        '0;JMP',
        "(GT_#{line})",
        # true part
        '@SP',
        'A=M-1',
        'M=-1',
        "(END_#{line})"
      ]
    end

    def translate_arithmetic_eq(_command, line)
      [
        "\n// eq ",
        'AM=M-1',
        'D=M',
        'A=A-1',
        'D=M-D',
        "@EQ_#{line}",
        # false part
        'D;JEQ',
        '@SP',
        'A=M-1',
        'M=0',
        "@END_#{line}",
        '0;JMP',
        "(EQ_#{line})",
        # true part
        '@SP',
        'A=M-1',
        'M=-1',
        "(END_#{line})"
      ]
    end

    def translate_arithmetic_add(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'AM=M-1', # A = RAM[SP] - 1 , M = RAM[RAM[SP] - 1]
        'D=M', # D = RAM[RAM[SP] - 1]
        'A=A-1', # A = RAM[SP] - 2, M = RAM[RAM[SP] -2]
        'M=D+M' # RAM[RAM[SP] -2] = RAM[RAM[SP] - 1] + RAM[RAM[SP] -2]
      ]
    end

    # sub: x - y -- push x, push y
    def translate_arithmetic_sub(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'AM=M-1', # A = RAM[SP] - 1 , M = RAM[RAM[SP] - 1]
        'D=M', # D = RAM[RAM[SP] - 1]
        'A=A-1', # A = RAM[SP] - 2, M = RAM[RAM[SP] -2]
        'M=M-D' # RAM[RAM[SP] -2] = RAM[RAM[SP] - 1] + RAM[RAM[SP] -2]
      ]
    end

    # sub: -y
    def translate_arithmetic_neg(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'A=M-1',
        'M=-M'
      ]
    end

    # x and y -- bitwise
    def translate_logical_and(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'AM=M-1', # A = RAM[SP] - 1 , M = RAM[RAM[SP] - 1]
        'D=M', # D = RAM[RAM[SP] - 1]
        'A=A-1', # A = RAM[SP] - 2, M = RAM[RAM[SP] -2]
        'M=D&M' # RAM[RAM[SP] -2] = RAM[RAM[SP] - 1] + RAM[RAM[SP] -2]
      ]
    end

    # x or y -- bitwise
    def translate_logical_or(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'AM=M-1', # A = RAM[SP] - 1 , M = RAM[RAM[SP] - 1]
        'D=M', # D = RAM[RAM[SP] - 1]
        'A=A-1', # A = RAM[SP] - 2, M = RAM[RAM[SP] -2]
        'M=D|M' # RAM[RAM[SP] -2] = RAM[RAM[SP] - 1] + RAM[RAM[SP] -2]
      ]
    end

    # Not y -- bitwise
    def translate_logical_not(command, line)
      [
        "\n// #{command} line:#{line}",
        '@SP', # A=0, M = RAM[SP], M = *SP
        'A=M-1',
        'M=!M'
      ]
    end
  end
end