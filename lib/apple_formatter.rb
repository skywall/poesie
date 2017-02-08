require 'builder'

module Poesie
  module AppleFormatter

    # Write the Localizable.strings output file
    #
    # @param [Array<Hash<String, Any>>] terms
    #        JSON returned by the POEditor API
    # @param [String] file
    #        The path of the file to write
    # @param [Hash<String,String>] substitutions
    #        The list of substitutions to apply to the translations
    # @param [Bool] print_date
    #        Should we print the date in the header of the generated file
    #
    def self.write_strings_file(terms, file, substitutions: nil, print_date: false)
      out_lines = ['/'+'*'*79, ' * Exported from POEditor - https://poeditor.com']
      out_lines << " * #{Time.now}" if print_date
      out_lines += [' '+'*'*79+'/', '']
      last_prefix = ''
      stats = { :android => 0, :nil => [], :count => 0 }

      terms.each do |term|
        (term, definition, comment, context) = ['term', 'definition', 'comment', 'context'].map { |k| term[k] }

        # Filter terms and update stats
        next if (term.nil? || term.empty? || definition.nil? || definition.empty?) && stats[:nil] << term
        next if (term =~ /_android$/) && stats[:android] += 1 # Remove android-specific strings
        stats[:count] += 1

        # Generate MARK from prefixes
        prefix = %r(([^_]*)_.*).match(term)
        if prefix && prefix[1] != last_prefix
          last_prefix = prefix[1]
          mark = last_prefix[0].upcase + last_prefix[1..-1].downcase
          out_lines += ['', '/'*80, "// MARK: #{mark}"]
        end

        # If plural, use the text for the "one" (singular) entry
        if definition.is_a? Hash
          definition = definition["one"]
        end

        definition = Poesie::process(definition, substitutions)
                    .gsub("\u2028", '') # Sometimes inserted by the POEditor exporter
                    .gsub("\n", '\n') # Replace actual CRLF with '\n'
                    .gsub('"', '\\"') # Escape quotes
                    .gsub(/%(\d+\$)?s/, '%\1@') # replace %s with %@ for iOS
        out_lines << %Q(// CONTEXT: #{context.gsub("\n", '\n')}) unless context.empty?
        out_lines << %Q("#{term}" = "#{definition}";)
      end

      content = out_lines.join("\n") + "\n"

      Log::info(" - Save to file: #{file}")
      File.open(file, "w") do |fh|
        fh.write(content)
      end
      Log::info("   [Stats] #{stats[:count]} strings processed (Filtered out #{stats[:android]} android strings)")
      unless stats[:nil].empty?
        Log::error("   Found #{stats[:nil].count} empty value(s) for the following term(s):")
        stats[:nil].each { |key| Log::error("    - #{key.inspect}") }
      end
    end

    # Write the Localizable.stringsdict output file
    #
    # @param [Array<Hash<String, Any>>] terms
    #        JSON returned by the POEditor API
    # @param [String] file
    #        The path of the file to write
    # @param [Hash<String,String>] substitutions
    #        The list of substitutions to apply to the translations
    # @param [Bool] print_date
    #        Should we print the date in the header of the generated file
    #
    def self.write_stringsdict_file(terms, file, substitutions: nil, print_date: false)
      stats = { :android => 0, :nil => [], :count => 0 }

      Log::info(" - Save to file: #{file}")
      File.open(file, "w") do |fh|
        xml_builder = Builder::XmlMarkup.new(:target => fh, :indent => 4)
        xml_builder.instruct!
        xml_builder.comment!("Exported from POEditor   ")
        xml_builder.comment!(Time.now) if print_date
        xml_builder.comment!("see https://poeditor.com ")
        xml_builder.plist(:version => '1.0') do |plist_node|
          plist_node.dict do |root_node|
            terms.each do |term|
              (term, term_plural, definition) = ['term', 'term_plural', 'definition'].map { |k| term[k] }

              # Filter terms and update stats
              next if (term.nil? || term.empty? || definition.nil?) && stats[:nil] << term
              next if (term =~ /_android$/) && stats[:android] += 1 # Remove android-specific strings
              next unless definition.is_a? Hash
              stats[:count] += 1
              
              key = term_plural || term

              root_node.key(key)
              root_node.dict do |dict_node|
                dict_node.key('NSStringLocalizedFormatKey')
                dict_node.string('%#@format@')
                dict_node.key('format')
                dict_node.dict do |format_node|
                  format_node.key('NSStringFormatSpecTypeKey')
                  format_node.string('NSStringPluralRuleType')
                  format_node.key('NSStringFormatValueTypeKey')
                  format_node.string('d')

                  definition.each do |(quantity, text)|
                    text = Poesie::process(text, substitutions)
                    text = Poesie::process(text, substitutions)
                              .gsub("\u2028", '') # Sometimes inserted by the POEditor exporter
                              .gsub('\n', "\n") # Replace '\n' with actual CRLF
                              .gsub(/%(\d+\$)?s/, '%\1@') # replace %s with %@ for iOS
                    format_node.key(quantity)
                    format_node.string(text)
                  end
                end
              end
            end
          end
        end
      end
      Log::info("   [Stats] #{stats[:count]} strings processed (Filtered out #{stats[:android]} android strings)")
      unless stats[:nil].empty?
        Log::error("   Found #{stats[:nil].count} empty value(s) for the following term(s):")
        stats[:nil].each { |key| Log::error("    - #{key.inspect}") }
      end
    end

    # Write the JSON output file containing all context keys
    #
    # @param [Array<Hash<String, Any>>] terms
    #        JSON returned by the POEditor API
    # @param [String] file
    #        The path of the file to write
    #
    def self.write_context_json(terms, file)
      json_hash = { "date" => "#{Time.now}" }

      stats = { :android => 0, :nil => 0, :count => 0 }

      #switch on term / context
      array_context = Array.new
      terms.each do |term|
        (term, definition, comment, context) = ['term', 'definition', 'comment', 'context'].map { |k| term[k] }

        # Filter terms and update stats
        next if (term.nil? || term.empty? || context.nil? || context.empty?) && stats[:nil] += 1
        next if (term =~ /_android$/) && stats[:android] += 1 # Remove android-specific strings
        stats[:count] += 1

        # Escape some chars
        context = context
                    .gsub("\u2028", '') # Sometimes inserted by the POEditor exporter
                    .gsub("\\", "\\\\\\") # Replace actual \ with \\
                    .gsub('\\\\"', '\\"') # Replace actual \\" with \"
                    .gsub(/%(\d+\$)?s/, '%\1@') # replace %s with %@ for iOS

        array_context << { "term" => "#{term}", "context" => "#{context}" }
      end

      json_hash[:"contexts"] = array_context

      context_json = JSON.pretty_generate(json_hash)

      Log::info(" - Save to file: #{file}")
      File.open(file, "w") do |fh|
        fh.write(context_json)
      end
      Log::info("   [Stats] #{stats[:count]} contexts processed (Filtered out #{stats[:android]} android entries, #{stats[:nil]} nil contexts)")
    end

  end
end
