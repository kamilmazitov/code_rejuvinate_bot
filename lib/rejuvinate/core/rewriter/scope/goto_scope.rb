# frozen_string_literal: true

module Rejuvinate::Core
  # Go to and change its scope to a child node.
  class Rewriter::GotoScope < Rewriter::Scope
    # Initialize a GotoScope.
    #
    # @param instance [Rejuvinate::Core::Rewriter::Instance]
    # @param child_node_name [Symbol|String] name of child node
    # @yield run on the child node
    def initialize(instance, child_node_name, &block)
      super(instance, &block)
      @child_node_name = child_node_name
    end

    # Go to a child now, then run the block code on the the child node.
    def process
      current_node = @instance.current_node
      return unless current_node

      child_node = current_node
      @child_node_name.to_s.split('.').each do |child_node_name|
        child_node = child_node.is_a?(Array) && child_node_name =~ /-?\d+/ ? child_node[child_node_name.to_i] : child_node.send(child_node_name)
      end
      if child_node.is_a?(Array)
        child_node.each do |child_child_node|
          @instance.process_with_other_node child_child_node do
            @instance.instance_eval(&@block)
          end
        end
      else
        @instance.process_with_other_node child_node do
          @instance.instance_eval(&@block)
        end
      end
    end
  end
end
