# Memory Access Commands
# push segment index: Push the value of segment[index] on the stack
# pop segment index: Pop the top stock value and store it in segment[index]

module CommandType
  C_PUSH = 'c_push'.freeze
  C_POP = 'c_pop'.freeze
  C_ARITHMETIC = 'c_arithmetic'.freeze
end

# Read VM commands, parses them, and provide access to thier components
class Parser
  def initialize(file_name)
    @file_enumerator = File.foreach(file_name)
    @line = 0
  end

  def parse(code_writer)
    while has_more_commands
      advance
      case command_type
      when CommandType::C_PUSH
        puts "PUSH command line:#{@line}, #{arg1} #{arg2}"
        code_writer.write_push('push', arg1, arg2)
      when CommandType::C_POP
        puts "POP command line:#{@line}, #{arg1} #{arg2}"
      when CommandType::C_ARITHMETIC
        puts "ARITHMETIC command line:#{@line}, #{@current_command}"
        code_writer.write_arithmethic(@current_command, @line)
      else
        # puts "else line: #{@line}"
      end
    end
  end

  def arg1
    @current_command.split[1]
  end

  def arg2
    @current_command.split[2]
  end

  def advance
    @line += 1
    @current_command = @file_enumerator.next.strip
  end

  def has_more_commands
    @file_enumerator.peek
    true
  rescue StopIteration => ex
    return false
  end

  def command_type
    return CommandType::C_PUSH if @current_command.start_with?('push')
    return CommandType::C_POP if @current_command.start_with?('pop')
    return CommandType::C_ARITHMETIC if arithmetic_commands.include?(@current_command)
  end

  private

  # Pop two items off the stack, cumpute the compute the binary function on them,
  # and the push the result back on the stack
  # unary ones pops a single item
  # Each command has a net impack of replacing its operand(s) with commands result,
  # without affecting the rest of the stack
  def arithmetic_commands
    %w[
      add
      sub
      neg
      eq
      gt
      lt
      and
      or
      not
    ]
  end
end

# Translate VM commands into Hack assembly code
class CodeWriter
  def initialize(output_filename)
    @output_file = File.new(output_filename, 'a')
  end

  # Writes the assembly code that is the translation of given arithmetic command
  def write_arithmethic(command, line)
    translation = aritmetic_translation(command, line)
    @output_file.write(translation.join("\n"))
  end

  # Where the command is either C_POP or C_PUSH
  # push segment index
  def write_pushpop(_command, _segment, _index)
    puts 'Translate the given pop or push command'
  end

  def write_push(_command, _segment, index)
    @output_file.write(translate_push_constant(index).join("\n"))
    # @output_file.close
  end

  private

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

  def translate_push_constant(value)
    [
      "\n// push constant #{value}",
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
end

require 'pathname'

def main
  file_name = ARGV[0]
  parser = Parser.new(file_name)
  basename = File.basename(file_name, '.vm')
  code_writer = CodeWriter.new("#{basename}.asm")
  parser.parse(code_writer)
end

main