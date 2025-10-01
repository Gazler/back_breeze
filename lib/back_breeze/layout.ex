defmodule BackBreeze.Layout do
  @type direction :: :horizontal | :vertical
  @type flex :: :start | :center | :end | :space_between | :space_around | :space_evenly
  @type t :: %__MODULE__{
          direction: direction(),
          constraints: [BackBreeze.Layout.Constraint.t()],
          margin: BackBreeze.Layout.Margin.t(),
          flex: flex(),
          spacing: BackBreeze.Layout.Spacing.t()
        }

  defstruct constraints: [],
            direction: :vertical,
            margin: %BackBreeze.Layout.Margin{},
            flex: :start,
            spacing: %BackBreeze.Layout.Spacing{}

  alias Cassowary.Expression
  alias BackBreeze.Layout.Constraint
  alias BackBreeze.Layout
  alias BackBreeze.Layout.{Element, Margin, Spacing, Constants}
  alias BackBreeze.Rect
  alias Cassowary.{Solver, Variable}

  def new(direction, constraints, margin, flex) do
    %Layout{
      direction: direction,
      constraints: constraints,
      margin: margin,
      flex: flex
    }
  end

  def vertical() do
    %Layout{}
  end

  def horizontal() do
    %Layout{direction: :horizontal}
  end

  def constraints(%Layout{} = layout, constraints) do
    %{layout | constraints: constraints}
  end

  def direction(%Layout{} = layout, direction) do
    %{layout | direction: direction}
  end

  def margin(%Layout{} = layout, %Margin{} = margin) do
    %{layout | margin: margin}
  end

  def margin(%Layout{} = layout, margin) when is_integer(margin) and margin >= 0 do
    %{layout | margin: Margin.new(margin, margin)}
  end

  def margin(%Layout{} = layout, {h, v})
      when is_integer(h) and h >= 0 and is_integer(v) and v >= 0 do
    %{layout | margin: Margin.new(h, v)}
  end

  def flex(%Layout{} = layout, flex) do
    %{layout | flex: flex}
  end

  def spacing(%Layout{} = layout, %Spacing{} = spacing) do
    %{layout | spacing: spacing}
  end

  def spacing(%Layout{} = layout, spacing) when is_integer(spacing) do
    spacing =
      if spacing < 0 do
        Spacing.new(:overlap, abs(spacing))
      else
        Spacing.new(:space, abs(spacing))
      end

    %{layout | spacing: spacing}
  end

  @spec split(%Layout{}, Rect.t()) :: [Element.t()]
  def split(%Layout{constraints: []}, _rect) do
    []
  end

  def split(%Layout{} = layout, area) do
    layout
    |> do_split(area)
    |> elem(0)
  end

  @spec do_split(%Layout{}, Rect.t()) :: [Element.t()]
  defp do_split(layout, area) do
    solver = Solver.new()
    inner_area = Rect.inner(area, layout.margin)

    {area_start, area_end} =
      case layout.direction do
        :horizontal ->
          {inner_area.x * Constants.float_precision_multiplier(),
           Rect.right(inner_area) * Constants.float_precision_multiplier()}

        :vertical ->
          {inner_area.y * Constants.float_precision_multiplier(),
           Rect.bottom(inner_area) * Constants.float_precision_multiplier()}
      end

    variable_count = length(layout.constraints) * 2 + 2

    variables =
      Enum.map(1..variable_count, fn _ ->
        Variable.new()
      end)

    spacers =
      variables
      |> Enum.chunk_every(2)
      |> Enum.map(fn [a, b] ->
        Layout.Element.new(a, b)
      end)

    segments =
      variables
      |> Enum.drop(1)
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.map(fn [a, b] ->
        Layout.Element.new(a, b)
      end)

    flex = layout.flex

    spacing =
      case layout.spacing.type do
        :space -> layout.spacing.value
        :overlap -> -layout.spacing.value
      end

    constraints = layout.constraints
    area_size = Element.new(List.first(variables), List.last(variables))

    with {:ok, solver} <- configure_area(solver, area_size, area_start, area_end),
         {:ok, solver} <- configure_variable_in_area_constraints(solver, variables, area_size),
         {:ok, solver} <- configure_variable_constraints(solver, variables),
         {:ok, solver} <-
           configure_flex_constraints(solver, area_size, spacers, flex, spacing),
         {:ok, solver} <- configure_constraints(solver, area_size, segments, constraints),
         {:ok, solver} <- configure_fill_constraints(solver, segments, constraints),
         {:ok, solver} =
           segments
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.reduce({:ok, solver}, fn
             [left, right], {:ok, solver} ->
               Solver.add_constraint(
                 solver,
                 Element.has_size(left, right, Constants.all_segment_grow())
               )

             [_left, _right], {:error, reason} ->
               {:error, reason}
           end) do
      solver = Solver.fetch_changes(solver)
      changes = Enum.into(solver.public_changes, %{})

      segment_rects =
        changes_to_rects(changes, segments, inner_area, layout.direction)

      spacer_rects =
        changes_to_rects(changes, spacers, inner_area, layout.direction)

      {segment_rects, spacer_rects}
    end
  end

  @spec configure_area(Solver.t(), Element.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Solver.t()} | {:error, atom()}
  defp configure_area(solver, area, area_start, area_end) do
    with {:ok, solver} <-
           Solver.add_constraint(solver, Cassowary.Constraint.eq(area.start, area_start)),
         {:ok, solver} <-
           Solver.add_constraint(solver, Cassowary.Constraint.eq(area.end, area_end)) do
      {:ok, solver}
    end
  end

  @spec configure_variable_in_area_constraints(Solver.t(), [Variable.t()], Element.t()) ::
          {:ok, Solver.t()} | {:error, atom()}
  defp configure_variable_in_area_constraints(solver, variables, area) do
    variables
    |> Enum.slice(1..-2//1)
    |> Enum.reduce({:ok, solver}, fn
      variable, {:ok, solver} ->
        constraint = Cassowary.Constraint.ge(variable, area.start)

        with {:ok, solver} <- Solver.add_constraint(solver, constraint),
             constraint = Cassowary.Constraint.le(variable, area.end),
             {:ok, solver} <- Solver.add_constraint(solver, constraint) do
          {:ok, solver}
        end

      _variable, {:error, reason} ->
        {:error, reason}
    end)
  end

  @spec configure_variable_constraints(Solver.t(), [Variable.t()]) ::
          {:ok, Solver.t()} | {:error, atom()}
  defp configure_variable_constraints(solver, variables) do
    variables
    |> Enum.slice(1..-2//1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce({:ok, solver}, fn
      [left, right], {:ok, solver} ->
        Solver.add_constraint(solver, Cassowary.Constraint.le(left, right))

      [_left, _right], {:error, reason} ->
        {:error, reason}
    end)
  end

  @spec configure_flex_constraints(Solver.t(), Rect.t(), [Element.t()], flex(), number()) ::
          {:ok, Solver.t()} | {:error, atom()}
  defp configure_flex_constraints(solver, area, spacers, flex, spacing) do
    spacers_except_first_and_last = Enum.slice(spacers, 1..-2//1)
    spacing = spacing * Constants.float_precision_multiplier()

    case flex do
      :start ->
        {:ok, solver} =
          Enum.reduce(spacers_except_first_and_last, {:ok, solver}, fn
            spacer, {:ok, solver} ->
              Solver.add_constraint(
                solver,
                Element.has_size(spacer, spacing, Constants.spacer_size_eq())
              )

            _spacer, {:error, reason} ->
              {:error, reason}
          end)

        first = List.first(spacers)
        last = List.last(spacers)

        with {:ok, solver} <- Solver.add_constraint(solver, Element.is_empty(first)),
             {:ok, solver} <-
               Solver.add_constraint(solver, Element.has_size(last, area, Constants.grow())) do
          {:ok, solver}
        end

      :center ->
        first = List.first(spacers)
        last = List.last(spacers)

        with {:ok, solver} <-
               Enum.reduce(spacers_except_first_and_last, {:ok, solver}, fn
                 spacer, {:ok, solver} ->
                   Solver.add_constraint(
                     solver,
                     Element.has_size(spacer, spacing, Constants.spacer_size_eq())
                   )

                 _spacer, {:error, reason} ->
                   {:error, reason}
               end),
             {:ok, solver} <-
               Solver.add_constraint(solver, Element.has_size(first, area, Constants.grow())),
             {:ok, solver} <-
               Solver.add_constraint(solver, Element.has_size(last, area, Constants.grow())),
             {:ok, solver} <-
               Solver.add_constraint(
                 solver,
                 Element.has_size(first, last, Constants.spacer_size_eq())
               ) do
          {:ok, solver}
        end

      :end ->
        {:ok, solver} =
          Enum.reduce(spacers_except_first_and_last, {:ok, solver}, fn
            spacer, {:ok, solver} ->
              Solver.add_constraint(
                solver,
                Element.has_size(spacer, spacing, Constants.spacer_size_eq())
              )

            _spacer, {:error, reason} ->
              {:error, reason}
          end)

        with {:ok, solver} <-
               Solver.add_constraint(solver, Element.is_empty(List.last(spacers))),
             {:ok, solver} <-
               Solver.add_constraint(
                 solver,
                 Element.has_size(List.first(spacers), area, Constants.grow())
               ) do
          {:ok, solver}
        end

      :space_between ->
        with {:ok, solver} <-
               Enum.reduce(spacers_except_first_and_last, {:ok, solver}, fn
                 spacer, {:ok, solver} ->
                   Solver.add_constraint(
                     solver,
                     Element.has_size(spacer, spacing, Constants.spacer_size_eq())
                   )

                 _spacer, {:error, reason} ->
                   {:error, reason}
               end),
             {:ok, solver} <-
               spacers_except_first_and_last
               |> tuple_combinations()
               |> Enum.reduce({:ok, solver}, fn
                 {left, right}, {:ok, solver} ->
                   Solver.add_constraint(
                     solver,
                     Element.has_size(left, right, Constants.spacer_size_eq())
                   )

                 {_left, _right}, {:error, reason} ->
                   {:error, reason}
               end),
             {:ok, solver} <-
               Enum.reduce(spacers_except_first_and_last, {:ok, solver}, fn
                 spacer, {:ok, solver} ->
                   {:ok, solver} =
                     Solver.add_constraint(
                       solver,
                       Element.has_min_size(spacer, spacing, Constants.spacer_size_eq())
                     )

                   Solver.add_constraint(
                     solver,
                     Element.has_size(spacer, area, Constants.space_grow())
                   )

                 _spacer, {:error, reason} ->
                   {:error, reason}
               end),
             first = List.first(spacers),
             last = List.last(spacers),
             {:ok, solver} <- Solver.add_constraint(solver, Element.is_empty(first)),
             {:ok, solver} <- Solver.add_constraint(solver, Element.is_empty(last)) do
          {:ok, solver}
        end

      :space_around ->
        if length(spacers) <= 2 do
          {:ok, solver} =
            spacers
            |> tuple_combinations()
            |> Enum.reduce({:ok, solver}, fn
              {left, right}, {:ok, solver} ->
                Solver.add_constraint(
                  solver,
                  Element.has_size(left, right, Constants.spacer_size_eq())
                )

              {_left, _right}, {:error, reason} ->
                {:error, reason}
            end)

          Enum.reduce(spacers, {:ok, solver}, fn
            spacer, {:ok, solver} ->
              {:ok, solver} =
                Solver.add_constraint(
                  solver,
                  Element.has_min_size(spacer, spacing, Constants.spacer_size_eq())
                )

              Solver.add_constraint(
                solver,
                Element.has_size(spacer, area, Constants.space_grow())
              )

            _spacer, {:error, reason} ->
              {:error, reason}
          end)
        else
          [first | rest] = spacers
          {last, middle} = {List.last(rest), Enum.slice(rest, 0..-2//1)}
          first_middle = List.first(middle)

          with {:ok, solver} <-
                 middle
                 |> tuple_combinations()
                 |> Enum.reduce({:ok, solver}, fn
                   {left, right}, {:ok, solver} ->
                     Solver.add_constraint(
                       solver,
                       Element.has_size(left, right, Constants.spacer_size_eq())
                     )

                   {_left, _right}, {:error, reason} ->
                     {:error, reason}
                 end),
               {:ok, solver} <-
                 Solver.add_constraint(
                   solver,
                   Element.has_double_size(first_middle, first, Constants.spacer_size_eq())
                 ),
               {:ok, solver} <-
                 Solver.add_constraint(
                   solver,
                   Element.has_double_size(first_middle, last, Constants.spacer_size_eq())
                 ),
               {:ok, solver} <-
                 Enum.reduce(spacers, {:ok, solver}, fn
                   spacer, {:ok, solver} ->
                     with {:ok, solver} <-
                            Solver.add_constraint(
                              solver,
                              Element.has_min_size(spacer, spacing, Constants.spacer_size_eq())
                            ),
                          {:ok, solver} <-
                            Solver.add_constraint(
                              solver,
                              Element.has_size(spacer, area, Constants.space_grow())
                            ) do
                       {:ok, solver}
                     end

                   _spacer, {:error, reason} ->
                     {:error, reason}
                 end) do
            {:ok, solver}
          end
        end

      :space_evenly ->
        {:ok, solver} =
          spacers
          |> tuple_combinations()
          |> Enum.reduce({:ok, solver}, fn
            {left, right}, {:ok, solver} ->
              Solver.add_constraint(
                solver,
                Element.has_size(left, right, Constants.spacer_size_eq())
              )

            {_left, _right}, {:error, reason} ->
              {:error, reason}
          end)

        Enum.reduce(spacers, {:ok, solver}, fn
          spacer, {:ok, solver} ->
            with {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_min_size(spacer, spacing, Constants.spacer_size_eq())
                   ),
                 {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_size(spacer, area, Constants.space_grow())
                   ) do
              {:ok, solver}
            end

          _spacer, {:error, reason} ->
            {:error, reason}
        end)
    end
  end

  @spec configure_constraints(t(), Rect.t(), [Element.t()], [Constraint.t()]) ::
          {:ok, t()} | {:error, String.t()}
  defp configure_constraints(solver, area, segments, constraints) do
    constraints
    |> Enum.zip(segments)
    |> Enum.reduce({:ok, solver}, fn
      {constraint, segment}, {:ok, solver} ->
        case constraint do
          %Constraint{type: :max, value: max} ->
            with {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_max_size(segment, max, Constants.max_size_le())
                   ),
                 {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_int_size(segment, max, Constants.max_size_eq())
                   ) do
              {:ok, solver}
            end

          %Constraint{type: :min, value: min} ->
            with {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_min_size(segment, min, Constants.min_size_ge())
                   ),
                 {:ok, solver} <-
                   Solver.add_constraint(
                     solver,
                     Element.has_size(segment, area, Constants.fill_grow())
                   ) do
              {:ok, solver}
            end

          %Constraint{type: :length, value: length} ->
            constraint = Element.has_int_size(segment, length, Constants.length_size_eq())

            Solver.add_constraint(solver, constraint)

          %Constraint{type: :percentage, value: p} ->
            size =
              area
              |> Element.size()
              |> Expression.multiply(p)
              |> Expression.divide(100)

            Solver.add_constraint(
              solver,
              Element.has_size(segment, size, Constants.percentage_size_eq())
            )

          %Constraint{type: :ratio, value: {num, den}} ->
            size =
              Element.size(area)
              |> Expression.multiply(num)
              |> Expression.divide(max(den, 1))

            Solver.add_constraint(
              solver,
              Element.has_size(segment, size, Constants.ratio_size_eq())
            )

          %Constraint{type: :fill} ->
            Solver.add_constraint(
              solver,
              Element.has_size(segment, area, Constants.fill_grow())
            )
        end

      {_constraint, _segment}, {:error, reason} ->
        {:error, reason}
    end)
  end

  defp configure_fill_constraints(solver, segments, constraints) do
    constraints
    |> Enum.zip(segments)
    |> Enum.filter(fn {c, _} -> c.type in [:fill, :min] end)
    |> tuple_combinations()
    |> Enum.reduce({:ok, solver}, fn
      {{left_constraint, left_segment}, {right_constraint, right_segment}}, {:ok, solver} ->
        left_scaling_factor =
          case left_constraint do
            %Constraint{type: :fill, value: scale} -> max(scale, 1.0e-6)
            %Constraint{type: :min} -> 1.0
          end

        right_scaling_factor =
          case right_constraint do
            %Constraint{type: :fill, value: scale} -> max(scale, 1.0e-6)
            %Constraint{type: :min} -> 1.0
          end

        left =
          left_segment
          |> Element.size()
          |> Expression.multiply(right_scaling_factor)

        right =
          right_segment
          |> Element.size()
          |> Expression.multiply(left_scaling_factor)

        Solver.add_constraint(
          solver,
          Cassowary.Constraint.eq(left, right, Constants.grow())
        )

      {{_left_constraint, _left_segment}, {_right_constraint, _right_segment}},
      {:error, reason} ->
        {:error, reason}
    end)
  end

  @spec tuple_combinations([any()]) :: [{any(), any()}]
  def tuple_combinations(enum) do
    for {left, i} <- Enum.with_index(enum),
        {right, j} <- Enum.with_index(enum),
        i < j do
      {left, right}
    end
  end

  @spec changes_to_rects(map(), [Element.t()], Rect.t(), :horizontal | :vertical) :: [Rect.t()]
  defp changes_to_rects(changes, elements, area, direction) do
    Enum.map(elements, fn element ->
      start_value = Map.get(changes, element.start, 0.0)
      end_value = Map.get(changes, element.end, 0.0)
      start_value = round(round(start_value) / Constants.float_precision_multiplier())
      end_value = round(round(end_value) / Constants.float_precision_multiplier())
      size = end_value - start_value

      case direction do
        :horizontal ->
          Rect.new(start_value, area.y, size, area.height)

        :vertical ->
          Rect.new(area.x, start_value, area.width, size)
      end
    end)
  end
end
