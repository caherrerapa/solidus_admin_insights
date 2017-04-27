module Spree
  class ShippingCostReport < Spree::Report
    HEADERS = { name: :string, shipping_charge: :integer, revenue: :integer, shipping_cost_percentage: :integer }
    SEARCH_ATTRIBUTES = { start_date: :start_date, end_date: :end_date }
    SORTABLE_ATTRIBUTES = []

    def paginated?
      false
    end

    class Result < Spree::Report::TimedResult
      charts ShippingCostDistributionChart

      def build_empty_observations
        @_shipping_methods = @results.collect { |r| r['name'] }.uniq
        super
        @observations = @_shipping_methods.collect do |shipping_method|
          @observations.collect do |observation|
            _d_observation                          = observation.dup
            _d_observation.name                     = shipping_method
            _d_observation.revenue                  = 0
            _d_observation.shipping_charge          = 0
            _d_observation.shipping_cost_percentage = 0
            _d_observation
          end
        end.flatten
      end

      class Observation < Spree::Report::TimedObservation
        observation_fields [:name, :shipping_charge, :revenue, :shipping_cost_percentage]

        def describes?(result, time_scale)
          (name = result['name']) && super
        end

        def shipping_cost_percentage
          @shipping_cost_percentage.to_f
        end
      end
    end

    def report_query
      order_with_shipments =
        Spree::Order
          .where.not(completed_at: nil)
          .where(completed_at: @start_date..@end_date)
          .joins(:shipments)
          .select(
            'spree_shipments.id as shipment_id',
            'spree_orders.shipment_total as shipping_charge',
            'spree_orders.id as order_id',
            'spree_orders.total as order_total',
            *time_scale_selects('spree_orders')
          )

      ar_shipping_rates = Arel::Table.new(:spree_shipping_rates)
      ar_subquery       = Arel::Table.new(:results)

      with_rates =
        Spree::Report::QueryFragments.from_subquery(order_with_shipments)
          .join(ar_shipping_rates)
          .on(ar_shipping_rates[:shipment_id].eq(ar_subquery[:shipment_id]))
          .where(ar_shipping_rates[:selected].eq(true))
          .project(
            'SUM(shipping_charge) as shipping_charge',
            'SUM(order_total) as revenue',
            'shipping_method_id',
            *time_scale_columns,
          )
          .group(*time_scale_columns, :shipping_method_id)
          .order(*time_scale_columns)

      ar_shipping_methods = Arel::Table.new(:spree_shipping_methods)
      ar_subquery_with_rates = Arel::Table.new(:with_rates)

      Spree::Report::QueryFragments
        .from_subquery(with_rates, as: 'with_rates')
        .join(ar_shipping_methods)
        .on(ar_shipping_methods[:id].eq(ar_subquery_with_rates[:shipping_method_id]))
        .project(
          ar_shipping_methods[:id],
          'revenue',
          'shipping_charge',
          'shipping_method_id',
          'name',
          'ROUND((shipping_charge/revenue) * 100, 2) as shipping_cost_percentage',
          *time_scale_columns
        )
    end

  end
end
