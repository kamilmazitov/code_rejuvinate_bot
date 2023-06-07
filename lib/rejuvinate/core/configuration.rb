# frozen_string_literal: true

module Rejuvinate::Core
  class Configuration
    class << self
      attr_writer :root_path, :skip_paths, :only_paths, :show_run_process, :number_of_workers, :single_quote, :tab_width

      # Get the path.
      #
      # @return [String] default is '.'
      def root_path
        @root_path || '.'
      end

      # Get a list of skip paths.
      #
      # @return [Array<String>] default is [].
      def skip_paths
        @skip_paths || []
      end

      # Get a list of only paths.
      #
      # @return [Array<String>] default is [].
      def only_paths
        @only_paths || []
      end

      # Check if show run process.
      #
      # @return [Boolean] default is false
      def show_run_process
        @show_run_process || false
      end

      # Number of workers
      #
      # @return [Integer] default is 1
      def number_of_workers
        @number_of_workers || 1
      end

      # Use single quote or double quote.
      #
      # @return [Boolean] true if use single quote, default is true
      def single_quote
        @single_quote.nil? ? true : @single_quote
      end

      def tab_width
        @tab_width || 2
      end
    end
  end
end
