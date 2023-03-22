# frozen_string_literal: true

require_relative "node_mutation/version"

class NodeMutation
  class MethodNotSupported < StandardError; end
  class ConflictActionError < StandardError; end

  autoload :Adapter, "node_mutation/adapter"
  autoload :ParserAdapter, "node_mutation/parser_adapter"
  autoload :Action, 'node_mutation/action'
  autoload :AppendAction, 'node_mutation/action/append_action'
  autoload :DeleteAction, 'node_mutation/action/delete_action'
  autoload :InsertAction, 'node_mutation/action/insert_action'
  autoload :RemoveAction, 'node_mutation/action/remove_action'
  autoload :PrependAction, 'node_mutation/action/prepend_action'
  autoload :ReplaceAction, 'node_mutation/action/replace_action'
  autoload :ReplaceWithAction, 'node_mutation/action/replace_with_action'
  autoload :WrapAction, 'node_mutation/action/wrap_action'
  autoload :NoopAction, 'node_mutation/action/noop_action'
  autoload :Result, 'node_mutation/result'
  autoload :Strategy, 'node_mutation/strategy'
  autoload :Struct, 'node_mutation/struct'

  # @!attribute [r] actions
  #   @return [Array<NodeMutation::Struct::Action>]
  attr_reader :actions

  # @!attribute [rw] transform_proc
  #  @return [Proc] proc to transfor the actions
  attr_accessor :transform_proc

  class << self
    # Configure NodeMutation
    # @param [Hash] options options to configure
    # @option options [NodeMutation::Adapter] :adapter the adpater
    # @option options [NodeMutation::Strategy] :strategy the strategy
    # @option options [Integer] :tab_width the tab width
    def configure(options)
      if options[:adapter]
        @adapter = options[:adapter]
      end
      if options[:strategy]
        @strategy = options[:strategy]
      end
      if options[:tab_width]
        @tab_width = options[:tab_width].to_i
      end
    end

    # Get the adapter
    # @return [NodeMutation::Adapter] current adapter, by default is {NodeMutation::ParserAdapter}
    def adapter
      @adapter ||= ParserAdapter.new
    end

    def strategy
      @strategy ||= Strategy::KEEP_RUNNING
    end

    def tab_width
      @tab_width ||= 2
    end
  end

  def initialize(source)
    @source = source
    @actions = []
  end

  def append(node, code)
    @actions << AppendAction.new(node, code).process
  end

  def delete(node, *selectors, and_comma: false)
    @actions << DeleteAction.new(node, *selectors, and_comma: and_comma).process
  end

  def insert(node, code, at: 'end', to: nil, and_comma: false)
    @actions << InsertAction.new(node, code, at: at, to: to, and_comma: and_comma).process
  end

  def prepend(node, code)
    @actions << PrependAction.new(node, code).process
  end

  def remove(node, and_comma: false)
    @actions << RemoveAction.new(node, and_comma: and_comma).process
  end

  def replace(node, *selectors, with:)
    @actions << ReplaceAction.new(node, *selectors, with: with).process
  end

  def replace_with(node, code)
    @actions << ReplaceWithAction.new(node, code).process
  end

  def wrap(node, with:)
    @actions << WrapAction.new(node, with: with).process
  end

  def noop(node)
    @actions << NoopAction.new(node).process
  end

  def process
    if @actions.length == 0
      return NodeMutation::Result.new(affected: false, conflicted: false)
    end

    source = +@source
    @transform_proc.call(@actions) if @transform_proc
    @actions.sort_by! { |action| [action.start, action.end] }
    conflict_actions = get_conflict_actions
    if conflict_actions.size > 0 && strategy?(Strategy::THROW_ERROR)
      raise ConflictActionError, "mutation actions are conflicted"
    end

    @actions.reverse_each do |action|
      source[action.start...action.end] = action.new_code if action.new_code
    end
    result = NodeMutation::Result.new(affected: true, conflicted: !conflict_actions.empty?)
    result.new_source = source
    result
  end

  def test
    if @actions.length == 0
      return NodeMutation::Result.new(affected: false, conflicted: false)
    end

    @transform_proc.call(@actions) if @transform_proc
    @actions.sort_by! { |action| [action.start, action.end] }
    conflict_actions = get_conflict_actions
    if conflict_actions.size > 0 && strategy?(Strategy::THROW_ERROR)
      raise ConflictActionError, "mutation actions are conflicted"
    end

    result = NodeMutation::Result.new(affected: true, conflicted: !conflict_actions.empty?)
    result.actions = @actions
    result
  end

  private

  def get_conflict_actions
    i = @actions.length - 1
    j = i - 1
    conflict_actions = []
    return [] if i < 0

    begin_pos = @actions[i].start
    end_pos = @actions[i].end
    while j > -1
      # if we have two insert actions at same position.
      same_position = begin_pos == @actions[j].start && begin_pos == end_pos && @actions[j].start == @actions[j].end
      # if we have two actions with overlapped range.
      overlapped_position = begin_pos < @actions[j].end
      if (!strategy?(Strategy::ALLOW_INSERT_AT_SAME_POSITION) && same_position) || overlapped_position
        conflict_actions << @actions.delete_at(j)
      else
        i = j
        begin_pos = @actions[i].start
        end_pos = @actions[i].end
      end
      j -= 1
    end
    conflict_actions
  end

  def strategy?(strategy)
    NodeMutation.strategy & strategy == strategy
  end
end
