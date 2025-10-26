# frozen_string_literal: true

module Devagent
  # Enhanced Observer pattern: Pub-Sub event bus that allows multiple subscribers
  # to listen to agent events (plan, execute, test, etc.).
  #
  # This replaces the simple file-writing Tracer with a full event-driven architecture.
  #
  # Usage:
  #   event_bus = EventBus.new
  #
  #   # Subscribe to events
  #   event_bus.subscribe(:plan_generated) { |data| puts "New plan: #{data[:summary]}" }
  #   event_bus.subscribe(:action_executed) { |data| log_to_slack(data) }
  #   event_bus.subscribe(:tests_failed) { |data| notify_team(data) }
  #
  #   # Publish events
  #   event_bus.publish(:plan_generated, summary: "Add login feature", actions: [...])
  #   event_bus.publish(:action_executed, type: "fs_write", path: "lib/auth.rb")
  #
  # Benefits:
  #   - Loose coupling: subscribers don't know about each other
  #   - Easy extensibility: add new subscribers without changing core code
  #   - Better testing: can subscribe test doubles
  #   - Multiple outputs: file, UI, Slack, webhook, etc.
  class EventBus
    def initialize
      @subscribers = {}
    end

    # Subscribe to an event type with a callback block
    #
    # @param event_type [Symbol] The type of event to listen to
    # @yield [Hash] The event data payload
    # @example
    #   event_bus.subscribe(:plan_generated) { |data| puts data[:summary] }
    def subscribe(event_type, &callback)
      @subscribers[event_type] ||= []
      @subscribers[event_type] << callback
    end

    # Subscribe a handler object (with a #call method)
    #
    # @param event_type [Symbol] The type of event to listen to
    # @param handler [#call] An object that responds to #call
    # @example
    #   event_bus.subscribe(:plan_generated, Tracer.new)
    #   event_bus.subscribe(:action_executed, SlackNotifier.new)
    def subscribe_handler(event_type, handler)
      subscribe(event_type) { |data| handler.call(event_type, data) }
    end

    # Unsubscribe a specific callback
    #
    # @param event_type [Symbol] The type of event
    # @param callback [Proc] The callback to remove
    def unsubscribe(event_type, callback)
      @subscribers[event_type]&.delete(callback)
    end

    # Publish an event to all subscribers
    #
    # @param event_type [Symbol] The type of event
    # @param data [Hash] The event payload
    # @example
    #   event_bus.publish(:plan_generated, summary: "Added login", confidence: 0.8)
    def publish(event_type, data = {})
      return unless @subscribers[event_type]

      @subscribers[event_type].each do |callback|
        callback.call(data)
      rescue StandardError => e
        # Never let a subscriber crash the agent
        warn("EventBus subscriber error for #{event_type}: #{e.message}")
      end
    end

    # List all subscribed event types
    #
    # @return [Array<Symbol>] Event types with subscribers
    def subscribed_types
      @subscribers.keys
    end

    # Get subscriber count for an event type
    #
    # @param event_type [Symbol] The type of event
    # @return [Integer] Number of subscribers
    def subscriber_count(event_type)
      @subscribers[event_type]&.size || 0
    end

    # Clear all subscribers (useful for testing)
    def clear!
      @subscribers.clear
    end
  end

  # Adapter that wraps the old Tracer API to work with EventBus
  #
  # This allows backward compatibility while adding the new event system.
  #
  # Usage:
  #   event_bus = EventBus.new
  #   file_tracer = EventBus::FileTracerAdapter.new(repo_path)
  #   event_bus.subscribe_handler(:plan, file_tracer)
  #   event_bus.subscribe_handler(:execute_action, file_tracer)
  #
  #   # Old code still works:
  #   tracer = Tracer.new(repo_path)
  #   tracer.event("plan", summary: "...")
  #
  #   # New code uses EventBus:
  #   event_bus.publish(:plan, summary: "...")
  module EventBusAdapter
    # Adapter that saves events to a JSONL file (like old Tracer)
    class FileTracerAdapter
      def initialize(repo_path)
        @tracer = Tracer.new(repo_path)
      end

      def call(event_type, data)
        @tracer.event(event_type, data)
      end
    end

    # Adapter that logs to console (for UI updates)
    class ConsoleLoggerAdapter
      def initialize(output = $stdout)
        @output = output
      end

      def call(event_type, data)
        case event_type
        when :plan_generated
          @output.puts("✓ Plan: #{data[:summary]} (#{(data[:confidence] * 100).round}%)")
        when :action_executed
          @output.puts("✓ Executed: #{data[:type]} -> #{data[:path]}")
        when :tests_failed
          @output.puts("✗ Tests failed, replanning...")
        when :indexing_complete
          @output.puts("✓ Indexed #{data[:count]} files")
        end
      end
    end

    # Adapter that sends events to a webhook
    class WebhookAdapter
      def initialize(url)
        @url = url
      end

      def call(_event_type, _data)
        # POST to webhook
        # HTTP.post(@url, json: { event: event_type, data: data })
        nil # TODO: implement HTTP client
      end
    end
  end
end
