# frozen_string_literal: true

require 'parallel'
require 'fileutils'

module Rejuvinate::Core
  # Rewriter is the top level namespace in a snippet.
  #
  # One Rewriter checks if the depndency version matches, and it can contain one or many {Rejuvinate::Core::Rewriter::Instance},
  # which define the behavior what files and what codes to detect and rewrite to what code.
  class Rewriter
    DEFAULT_OPTIONS = { run_instance: true, write_to_file: true, adapter: 'parser' }.freeze

    autoload :ReplaceErbStmtWithExprAction, 'rejuvinate/core/rewriter/action/replace_erb_stmt_with_expr_action'

    autoload :Warning, 'rejuvinate/core/rewriter/warning'

    autoload :Instance, 'rejuvinate/core/rewriter/instance'

    autoload :Scope, 'rejuvinate/core/rewriter/scope'
    autoload :WithinScope, 'rejuvinate/core/rewriter/scope/within_scope'
    autoload :GotoScope, 'rejuvinate/core/rewriter/scope/goto_scope'

    autoload :Condition, 'rejuvinate/core/rewriter/condition'
    autoload :IfExistCondition, 'rejuvinate/core/rewriter/condition/if_exist_condition'
    autoload :UnlessExistCondition, 'rejuvinate/core/rewriter/condition/unless_exist_condition'
    autoload :IfOnlyExistCondition, 'rejuvinate/core/rewriter/condition/if_only_exist_condition'

    autoload :Helper, 'rejuvinate/core/rewriter/helper'

    autoload :RubyVersion, 'rejuvinate/core/rewriter/ruby_version'
    autoload :GemSpec, 'rejuvinate/core/rewriter/gem_spec'

    class << self
      # Register a rewriter with its group and name.
      #
      # @param group [String] the rewriter group.
      # @param name [String] the unique rewriter name.
      # @param rewriter [Rejuvinate::Core::Rewriter] the rewriter to register.
      def register(group, name, rewriter)
        group = group.to_s
        name = name.to_s
        rewriters[group] ||= {}
        rewriters[group][name] = rewriter
      end

      # Fetch a rewriter by group and name.
      #
      # @param group [String] rewrtier group.
      # @param name [String] rewrtier name.
      # @return [Rejuvinate::Core::Rewriter] the matching rewriter.
      def fetch(group, name)
        group = group.to_s
        name = name.to_s
        rewriters.dig(group, name)
      end

      # Get all available rewriters
      #
      # @return [Hash<String, Hash<String, Rewriter>>]
      def availables
        rewriters
      end

      # Clear all registered rewriters.
      def clear
        rewriters.clear
      end

      private

      def rewriters
        @rewriters ||= {}
      end
    end

    # @!attribute [r] group
    #   @return [String] the group of rewriter
    # @!attribute [r] name
    #   @return [String] the unique name of rewriter
    # @!attribute [r] sub_snippets
    #   @return [Array<Rejuvinate::Core::Rewriter>] all rewriters this rewiter calls.
    # @!attribute [r] helper
    #   @return [Array] helper methods.
    # @!attribute [r] warnings
    #   @return [Array<Rejuvinate::Core::Rewriter::Warning>] warning messages.
    # @!attribute [r] affected_files
    #   @return [Set] affected fileds
    # @!attribute [r] ruby_version
    #   @return [Rewriter::RubyVersion] the ruby version
    # @!attribute [r] gem_spec
    #   @return [Rewriter::GemSpec] the gem spec
    # @!attribute [r] test_results
    #   @return [Array<Object>] the test results
    # @!attribute [rw] options
    #   @return [Hash] the rewriter options
    attr_reader :group,
                :name,
                :sub_snippets,
                :helpers,
                :warnings,
                :affected_files,
                :ruby_version,
                :gem_spec,
                :test_results
    attr_accessor :options

    # Initialize a Rewriter.
    # When a rewriter is initialized, it is already registered.
    #
    # @param group [String] group of the rewriter.
    # @param name [String] name of the rewriter.
    # @yield defines the behaviors of the rewriter, block code won't be called when initialization.
    def initialize(group, name, &block)
      @group = group
      @name = name
      @block = block
      @helpers = []
      @sub_snippets = []
      @warnings = []
      @affected_files = Set.new
      @redo_until_no_change = false
      @options = DEFAULT_OPTIONS.dup
      @test_results = []
      self.class.register(@group, @name, self)
    end

    # Process the rewriter.
    # It will call the block.
    def process
      @affected_files = Set.new
      ensure_current_adapter do
        instance_eval(&@block)
      end

      process if !@affected_files.empty? && @redo_until_no_change # redo
    end

    def process_with_sandbox
      @options[:run_instance] = false
      process
    end

    def test
      @options[:write_to_file] = false
      @affected_files = Set.new
      ensure_current_adapter do
        instance_eval(&@block)
      end

      if !@affected_files.empty? && @redo_until_no_change # redo
        test
      end
      @test_results
    end

    def add_warning(warning)
      @warnings << warning
    end


    def add_affected_file(file_path)
      @affected_files.add(file_path)
    end

    def configure(options)
      @options = @options.merge(options)
      if @options[:adapter] == 'syntax_tree'
        NodeQuery.configure(adapter: NodeQuery::SyntaxTreeAdapter.new)
        NodeMutation.configure(adapter: NodeMutation::SyntaxTreeAdapter.new)
      else
        NodeQuery.configure(adapter: NodeQuery::ParserAdapter.new)
        NodeMutation.configure(adapter: NodeMutation::ParserAdapter.new)
      end
    end

    def description(description = nil)
      if description
        @description = description
      else
        @description
      end
    end

    def if_ruby(version)
      @ruby_version = Rewriter::RubyVersion.new(version)
    end

    def if_gem(name, version)
      @gem_spec = Rewriter::GemSpec.new(name, version)
    end

    def within_files(file_patterns, &block)
      return unless @options[:run_instance]

      return if @ruby_version && !@ruby_version.match?
      return if @gem_spec && !@gem_spec.match?

      if @options[:write_to_file]
        handle_one_file(Array(file_patterns)) do |file_path|
          instance = Rewriter::Instance.new(self, file_path, &block)
          instance.process
        end
      else
        results =
          handle_one_file(Array(file_patterns)) do |file_path|
            instance = Rewriter::Instance.new(self, file_path, &block)
            instance.test
          end
        merge_test_results(results)
      end
    end

    alias within_file within_files

    def add_file(filename, content)
      return unless @options[:run_instance]

      unless @options[:write_to_file]
        result = NodeMutation::Result.new(affected: true, conflicted: false)
        result.actions = [NodeMutation::Struct::Action.new(:add_file, 0, 0, content)]
        result.file_path = filename
        @test_results << result
        return
      end

      filepath = File.join(Configuration.root_path, filename)
      if File.exist?(filepath)
        puts "File #{filepath} already exists."
        return
      end

      FileUtils.mkdir_p File.dirname(filepath)
      File.write(filepath, content)
    end

    def remove_file(filename)
      return unless @options[:run_instance]

      unless @options[:write_to_file]
        result = NodeMutation::Result.new(affected: true, conflicted: false)
        result.actions = [NodeMutation::Struct::Action.new(:remove_file, 0, -1)]
        result.file_path = filename
        @test_results << result
        return
      end

      file_path = File.join(Configuration.root_path, filename)
      File.delete(file_path) if File.exist?(file_path)
    end

    def add_snippet(group, name = nil)
      rewriter =
        if name
          Rewriter.fetch(group, name) || Utils.eval_snippet([group, name].join('/'))
        else
          Utils.eval_snippet(group)
        end
      return unless rewriter && rewriter.is_a?(Rewriter)

      rewriter.options = @options
      if !rewriter.options[:write_to_file]
        results = rewriter.test
        merge_test_results(results)
      elsif rewriter.options[:run_instance]
        rewriter.process
      else
        rewriter.process_with_sandbox
      end
      @sub_snippets << rewriter
    end

    def helper_method(name, &block)
      @helpers << { name: name, block: block }
    end

    def redo_until_no_change
      @redo_until_no_change = true
    end

    private

    def ensure_current_adapter
      current_query_adapter = NodeQuery.adapter
      current_mutation_adapter = NodeMutation.adapter
      begin
        yield
      ensure
        NodeQuery.configure(adapter: current_query_adapter)
        NodeMutation.configure(adapter: current_mutation_adapter)
      end
    end

    def handle_one_file(file_patterns)
      if Configuration.number_of_workers > 1
        Parallel.map(Utils.glob(file_patterns), in_processes: Configuration.number_of_workers) do |file_path|
          yield(file_path)
        end
      else
        Utils.glob(file_patterns).map do |file_path|
          yield(file_path)
        end
      end
    end

    def merge_test_results(results)
      @test_results += results.compact.select { |result| result.affected? }
    end
  end
end
