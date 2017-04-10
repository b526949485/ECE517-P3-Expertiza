module PenaltyHelper

  def self.calculate_penalty(participant_id)
    @submission_deadline_type_id = 1
    @review_deadline_type_id = 2
    @meta_review_deadline_type_id = 5

    @participant = AssignmentParticipant.find(participant_id)
    @assignment = @participant.assignment
    if @assignment.late_policy_id
      @penalty_per_unit = LatePolicy.find(@assignment.late_policy_id).penalty_per_unit
      @max_penalty_for_no_submission = LatePolicy.find(@assignment.late_policy_id).max_penalty
      @penalty_unit = LatePolicy.find(@assignment.late_policy_id).penalty_unit
    end

    penalties = Hash.new(0)

    calculate_penalty = @assignment.calculate_penalty
    if calculate_penalty == true # TODO: add calculate_penalty column to the assignment table and use its value to check if the penalty is to be calculated for the assignment or not
      topic_id = SignedUpTeam.topic_id(@participant.parent_id, @participant.user_id)
      stage = @assignment.get_current_stage(topic_id)
      if stage == "Finished"
        penalties[:submission] = calculate_submission_penalty
        penalties[:review] = calculate_review_penalty
        penalties[:meta_review] = calculate_meta_review_penalty
      end
    else
      penalties[:submission] = 0
      penalties[:review] = 0
      penalties[:meta_review] = 0
    end

    penalties
  end

  def self.calculate_submission_penalty
    penalty = 0
    submission_due_date = AssignmentDueDate.where(deadline_type_id: @submission_deadline_type_id, parent_id:  @assignment.id).first.due_at

    resubmission_times = @participant.resubmission_times
    if resubmission_times.any?
      last_submission_time = resubmission_times.at(resubmission_times.size - 1).resubmitted_at
      if last_submission_time > submission_due_date
        time_difference = last_submission_time - submission_due_date
        penalty_units = calculate_penalty_units(time_difference, @penalty_unit)
        penalty_for_submission = penalty_units * @penalty_per_unit
        penalty = if penalty_for_submission > @max_penalty_for_no_submission
                    @max_penalty_for_no_submission
                  else
                    penalty_for_submission
                  end
      end
    else
      penalty = @max_penalty_for_no_submission
    end
  end

  def self.calculate_review_penalty
    penalty = 0
    num_of_reviews_required = @assignment.num_reviews
    if num_of_reviews_required > 0

      # reviews
      review_mappings = ReviewResponseMap.where(reviewer_id: @participant.id)

      review_due_date = AssignmentDueDate.where(deadline_type_id: @review_deadline_type_id, parent_id:  @assignment.id).first

      unless review_due_date.nil?
        penalty = compute_penalty_on_reviews(review_mappings, review_due_date.due_at, num_of_reviews_required)
      end
    end
    penalty
  end

  def self.calculate_meta_review_penalty
    penalty = 0
    num_of_meta_reviews_required = @assignment.num_review_of_reviews
    if num_of_meta_reviews_required > 0

      meta_review_mappings = MetareviewResponseMap.where(reviewer_id: @participant.id)

      meta_review_due_date = AssignmentDueDate.where(deadline_type_id: @meta_review_deadline_type_id, parent_id:  @assignment.id).first

      unless meta_review_due_date.nil?
        penalty = compute_penalty_on_reviews(meta_review_mappings, meta_review_due_date.due_at, num_of_meta_reviews_required)
      end
    end
    penalty
  end

  def self.compute_penalty_on_reviews(review_mappings, review_due_date, num_of_reviews_required)
    review_map_created_at_list = []

    penalty = 0

    # Calculate the number of reviews that the user has completed so far.
    review_mappings.each do |map|
      unless map.response.empty?
        created_at = Response.find_by_map_id(map.id).created_at
        review_map_created_at_list << created_at
      end
    end

    review_map_created_at_list.sort!

    for i in 0...num_of_reviews_required
      if review_map_created_at_list.at(i)
        if review_map_created_at_list.at(i) > review_due_date
          time_difference = review_map_created_at_list.at(i) - review_due_date
          penalty_units = calculate_penalty_units(time_difference, @penalty_unit)
          
          penalty_for_this_review = penalty_units * @penalty_per_unit
          if penalty_for_this_review > @max_penalty_for_no_submission
            penalty = @max_penalty_for_no_submission
          else
            penalty += penalty_for_this_review
          end
        end
      elsif
        penalty = @max_penalty_for_no_submission
      end
    end
    penalty
  end

  def self.calculate_penalty_units(time_difference, penalty_unit)
    penalty_units = 0
    
    if penalty_unit == 'Minute'
      penalty_units = time_difference / 60
    elsif penalty_unit == 'Hour'
      penalty_units = time_difference / 3600
    elsif penalty_unit == 'Day'
      penalty_units = time_difference / 86_400
    end
    
    return penalty_units
  end

  # checking that penalty_per_unit is not exceeding max_penalty
  def self.check_penalty_points_validity(max_penalty, penalty_per_unit)
    return false unless max_penalty < penalty_per_unit
    return true
  end

  # method to check whether the policy name given as a parameter already exists under the current instructor id
  #it return true if there's another policy with the same name under current instructor else false
  def self.check_policy_with_same_name(late_policy_name, instructor_id)
    @policy = LatePolicy.where(policy_name: late_policy_name)
    if !@policy.nil? && !@policy.empty?
      @policy.each do |p|
        next unless p.instructor_id == instructor_id
        return true
      end
    end
    return false
  end

  # this method updates all the penalty objects which uses the penalty policy which is passed as a parameter
  # whenever a policy is updated, all the existing penalty objects needs to be updated according to new policy
  def self.update_calculated_penalty_objects(penalty_policy)
    @penalty_objs = CalculatedPenalty.all
    @penalty_objs.each do |pen|
      @participant = AssignmentParticipant.find(pen.participant_id)
      @assignment = @participant.assignment
      next unless @assignment.late_policy_id == penalty_policy.id
      @penalties = calculate_penalty(pen.participant_id)
      @total_penalty = (@penalties[:submission] + @penalties[:review] + @penalties[:meta_review])
      if pen.deadline_type_id.to_i == 1
        {penalty_points: @penalties[:submission]}
        pen.update_attribute(:penalty_points, @penalties[:submission])
      elsif pen.deadline_type_id.to_i == 2
        {penalty_points: @penalties[:review]}
        pen.update_attribute(:penalty_points, @penalties[:review])
      elsif pen.deadline_type_id.to_i == 5
        {penalty_points: @penalties[:meta_review]}
        pen.update_attribute(:penalty_points, @penalties[:meta_review])
      end
    end
  end
end