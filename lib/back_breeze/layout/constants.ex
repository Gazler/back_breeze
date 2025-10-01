defmodule BackBreeze.Layout.Constants do
  alias Cassowary.Strength

  @float_precision_multiplier 100.0
  def float_precision_multiplier, do: @float_precision_multiplier

  @spacer_size_eq Strength.required() / 10.0
  def spacer_size_eq, do: @spacer_size_eq

  @grow Strength.medium() / 10.0
  def grow, do: @grow

  @space_grow Strength.weak() * 10.0
  def space_grow, do: @space_grow

  @max_size_le Strength.strong() * 100.0
  def max_size_le, do: @max_size_le

  @max_size_eq Strength.medium() * 10.0
  def max_size_eq, do: @max_size_eq

  @fill_grow Strength.medium()
  def fill_grow, do: @fill_grow

  @min_size_eq Strength.medium() * 10.0
  def min_size_eq, do: @min_size_eq

  @min_size_ge Strength.strong() * 100.0
  def min_size_ge, do: @min_size_ge

  @length_size_eq Strength.strong() * 10.0
  def length_size_eq, do: @length_size_eq

  @percentage_size_eq Strength.strong()
  def percentage_size_eq, do: @percentage_size_eq

  @ratio_size_eq Strength.strong() / 10.0
  def ratio_size_eq, do: @ratio_size_eq

  @all_segment_grow Strength.weak()
  def all_segment_grow, do: @all_segment_grow
end
