# frozen_string_literal: true

module Devagent
  # AgentState is the controller-owned "brain" for a single run.
  #
  # LLMs can propose plans, but the controller owns phase progression, tool gating,
  # observations, and hard stops.
  AgentState = Struct.new(
    :goal,
    :phase,
    :intent,
    :intent_confidence,
    :plan,
    :artifacts,
    :observations,
    :errors,
    :summary,
    :confidence,
    :cycle,
    :tool_rejections,
    :current_step,
    :step_results,
    :files_read_meta,
    :plan_fingerprints,
    :clarification_asked,
    :last_decision,
    :last_decision_confidence,
    :last_error_signature,
    :repeat_error_count,
    :retrieved_files,
    :retrieval_cached,
    keyword_init: true
  ) do
    PHASES = %i[intent planning execution observation reduction decision done halted].freeze

    def self.initial(goal:)
      new(
        goal: goal,
        phase: :intent,
        intent: nil,
        intent_confidence: 0.0,
        plan: nil,
        artifacts: {
          files_read: Set.new,
          files_written: Set.new,
          patches_applied: 0,
          commands_run: []
        },
        observations: [],
        errors: [],
        summary: nil,
        confidence: 0.0,
        cycle: 0,
        tool_rejections: 0,
        current_step: 0,
        step_results: {},
        files_read_meta: {},
        plan_fingerprints: Set.new,
        clarification_asked: false,
        last_decision: nil,
        last_decision_confidence: nil,
        last_error_signature: nil,
        repeat_error_count: 0,
        retrieved_files: [],
        retrieval_cached: false
      )
    end

    def record_file_read(path, meta: nil)
      p = path.to_s
      artifacts[:files_read] << p
      files_read_meta[p] = meta if meta
    end

    def record_file_written(path)
      artifacts[:files_written] << path.to_s
    end

    def record_patch_applied
      artifacts[:patches_applied] += 1
    end

    def record_command(command)
      artifacts[:commands_run] << command.to_s
    end

    def record_observation(obs)
      observations << obs
    end

    def record_error(signature:, message:)
      errors << { "signature" => signature.to_s, "message" => message.to_s }
      if last_error_signature == signature.to_s
        self.repeat_error_count += 1
      else
        self.last_error_signature = signature.to_s
        self.repeat_error_count = 1
      end
    end

    # Record retrieved files (once per goal)
    def record_retrieval(files, cached: false)
      self.retrieved_files = Array(files)
      self.retrieval_cached = cached
    end

    # Check if a path is in the retrieved files (or if no retrieval constraint)
    def path_in_retrieved?(path)
      retrieved_files.empty? || retrieved_files.include?(path.to_s)
    end
  end
end
