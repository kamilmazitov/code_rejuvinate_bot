# frozen_string_literal: true

module Rejuvinate::Core
  # IfExistCondition checks if matching node exists in the node children.
  class Rewriter::IfExistCondition < Rewriter::Condition
    private

    # check if any child node matches.
    #
    # @return [Boolean]
    def match?
      @node_query.query_nodes(target_node, including_self: false, stop_at_first_match: true).size > 0
    end
  end
end
