# frozen_string_literal: true

module Rejuvinate::Core
  # Scope finds out nodes which match rules.
  class Rewriter::Scope
    # Initialize a Scope
    #
    # @param instance [Rejuvinate::Core::Rewriter::Instance]
    # @yield run on a scope
    def initialize(instance, &block)
      @instance = instance
      @block = block
    end
  end
end
