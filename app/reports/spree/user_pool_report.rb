module Spree
  class UserPoolReport < Spree::Report
    HEADERS = { guest_users: :integer, active_users: :integer, new_sign_ups: :integer }
    SEARCH_ATTRIBUTES = { start_date: :users_created_from, end_date: :users_created_till }
    SORTABLE_ATTRIBUTES = []

    class Result < Spree::Report::TimedResult
      charts DistributionColumnChart

      class Observation < Spree::Report::TimedObservation
        observation_fields active_users: 0, guest_users: 0, new_sign_ups: 0
      end
    end

    def paginated?
      false
    end

    def report_query
      Report::QueryFragments
        .from_union(grouped_sign_ups, grouped_visitors)
        .group(*time_scale_columns)
        .order(*time_scale_columns_to_s)
        .project(
          *time_scale_columns,
          'SUM(active_users) as active_users',
          'SUM(guest_users) as guest_users',
          'SUM(new_sign_ups) as new_sign_ups'
        )
    end

    def grouped_sign_ups
      sign_ups = Spree::User.where(created_at: @start_date..@end_date).select(:id, *time_scale_selects)

      Report::QueryFragments.from_subquery(sign_ups)
        .group(*time_scale_columns, 'guest_users', 'active_users')
        .order(*time_scale_columns_to_s)
        .project(
          *time_scale_columns,
          '0 as guest_users',
          '0 as active_users',
          'COUNT(id) as new_sign_ups'
        )
    end

    def grouped_visitors
      visitors = Spree::PageEvent.where(created_at: @start_date..@end_date).select(*time_scale_selects, 'actor_id AS user', 'session_id AS session')
      Report::QueryFragments.from_subquery(visitors)
        .group(*time_scale_columns, 'new_sign_ups')
        .order(*time_scale_columns_to_s)
        .project(
          *time_scale_columns,
          '(COUNT(DISTINCT(session)) - COUNT(DISTINCT(user))) AS guest_users',
          'COUNT(DISTINCT(user)) as active_users', '0 as new_sign_ups'
        )
    end

  end
end
