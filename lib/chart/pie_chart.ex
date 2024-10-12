defmodule Contex.PieChart do
  @moduledoc """
  A Pie Chart that displays data in a circular graph.

  The pieces of the graph are proportional to the fraction of the whole in each category.
  Each slice of the pie is relative to the size of that category in the group as a whole.
  The entire “pie” represents 100 percent of a whole, while the pie “slices” represent portions of the whole.

  Fill colours for each slice can be specified with `colour_palette` parameter in chart options, or can be
  applied from a `CategoryColourScale` suppled in the `colour_scale` parameter. If neither option is supplied
  a default colour palette is used.
  """

  alias __MODULE__
  alias Contex.{Dataset, Mapping, CategoryColourScale}

  defstruct [
    :dataset,
    :mapping,
    :options,
    :colour_scale
  ]

  @type t() :: %__MODULE__{}

  @required_mappings [
    category_col: :zero_or_one,
    value_col: :zero_or_one
  ]

  @default_options [
    width: 600,
    height: 400,
    colour_palette: :default,
    colour_scale: nil,
    data_labels: true
  ]

  @doc """
  Create a new PieChart struct from Dataset.

  Options may be passed to control the settings for the chart. Options available are:

    - `:data_labels` : `true` (default) or false - display labels for each slice value
    - `:colour_palette` : `:default` (default) or colour palette - see `colours/2`

  An example:
        data = [
          ["Cat", 10.0],
          ["Dog", 20.0],
          ["Hamster", 5.0]
        ]

        dataset = Dataset.new(data, ["Pet", "Preference"])

        opts = [
          mapping: %{category_col: "Pet", value_col: "Preference"},
          colour_palette: ["fbb4ae", "b3cde3", "ccebc5"],
          legend_setting: :legend_right,
          data_labels: false,
          title: "Why dogs are better than cats"
        ]

        Contex.Plot.new(dataset, Contex.PieChart, 600, 400, opts)
  """
  def new(%Dataset{} = dataset, options \\ []) when is_list(options) do
    options = check_options(options)
    options = Keyword.merge(@default_options, options)
    mapping = Mapping.new(@required_mappings, Keyword.get(options, :mapping), dataset)

    %PieChart{
      dataset: dataset,
      mapping: mapping,
      options: options,
      colour_scale: Keyword.get(options, :colour_scale)
    }
  end

  defp check_options(options) do
    colour_scale = check_colour_scale(Keyword.get(options, :colour_scale))
    Keyword.put(options, :colour_scale, colour_scale)
  end

  defp check_colour_scale(%CategoryColourScale{} = scale), do: scale
  defp check_colour_scale(_), do: nil

  @doc false
  def set_size(%PieChart{} = chart, width, height) do
    chart
    |> set_option(:width, width)
    |> set_option(:height, height)
  end

  @doc false
  def get_legend_scales(%PieChart{} = chart) do
    [get_colour_palette(chart)]
  end

  @doc """
  Overrides the default colours.

  Colours can either be a named palette defined in `Contex.CategoryColourScale` or a list of strings representing hex code
  of the colour as per CSS colour hex codes, but without the #. For example:

    ```
    barchart = BarChart.colours(barchart, ["fbb4ae", "b3cde3", "ccebc5"])
    ```

    The colours will be applied to the data series in the same order as the columns are specified in `set_val_col_names/2`
  """
  @deprecated "Set in new/2 options"
  @spec colours(PieChart.t(), Contex.CategoryColourScale.colour_palette()) ::
          PieChart.t()
  def colours(%PieChart{} = chart, colour_palette) when is_list(colour_palette) do
    set_option(chart, :colour_palette, colour_palette)
  end

  def colours(%PieChart{} = chart, colour_palette) when is_atom(colour_palette) do
    set_option(chart, :colour_palette, colour_palette)
  end

  def colours(%PieChart{} = chart, _) do
    set_option(chart, :colour_palette, :default)
  end

  @doc """
  Renders the PieChart to svg, including the svg wrapper, as a string or improper string list that
  is marked safe.
  """
  def to_svg(%PieChart{} = chart) do
    [
      "<g>",
      generate_slices(chart),
      "</g>"
    ]
  end

  def get_categories(%PieChart{dataset: dataset, mapping: mapping}) do
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    dataset.data
    |> Enum.map(&cat_accessor.(&1))
  end

  defp set_option(%PieChart{options: options} = plot, key, value) do
    options = Keyword.put(options, key, value)

    %{plot | options: options}
  end

  defp get_option(%PieChart{options: options}, key) do
    Keyword.get(options, key)
  end

  defp get_colour_palette(%PieChart{colour_scale: colour_scale}) when not is_nil(colour_scale) do
    colour_scale
  end

  defp get_colour_palette(%PieChart{} = chart) do
    get_categories(chart)
    |> CategoryColourScale.new()
    |> CategoryColourScale.set_palette(get_option(chart, :colour_palette))
  end

  defp generate_slices(%PieChart{} = chart) do
    height = get_option(chart, :height)
    with_labels? = get_option(chart, :data_labels)
    colour_palette = get_colour_palette(chart)

    r = height / 2
    stroke_circumference = 2 * :math.pi() * r / 2

    scale_values(chart)
    |> Enum.map_reduce({0, 0}, fn {value, category}, {idx, offset} ->
      text_rotation = rotate_for(value, offset)
      displayed_percentage_value = Float.round(value, 2)

      label =
        if with_labels? do
          ~s"""
            <text x="#{negate_if_flipped(r, text_rotation)}"
                  y="#{negate_if_flipped(r, text_rotation)}"
              text-anchor="middle"
              fill="transparent"
              color="white"
              class="#{if displayed_percentage_value <= 5.0, do: "contex-label-small", else: ""}"
              stroke-width="1"
              transform="rotate(#{text_rotation},#{r},#{r})
                         translate(#{r / 2}, #{negate_if_flipped(5, text_rotation)})
                         #{if need_flip?(text_rotation), do: "scale(-1,-1)"}"
            >
              #{displayed_percentage_value}%
            </text>
          """
        else
          ""
        end

      {
        ~s"""
          <circle r="#{r / 2}" cx="#{r}" cy="#{r}" fill="transparent"
            stroke="##{CategoryColourScale.colour_for_value(colour_palette, category)}"
            stroke-width="#{r}"
            stroke-dasharray="#{slice_value(value, stroke_circumference)} #{stroke_circumference}"
            stroke-dashoffset="-#{slice_value(offset, stroke_circumference)}">
          </circle>
          #{label}
        """,
        {idx + 1, offset + value}
      }
    end)
    |> elem(0)
    |> Enum.join()
  end

  defp slice_value(value, stroke_circumference) do
    value * stroke_circumference / 100
  end

  defp rotate_for(n, offset) do
    n / 2 * 3.6 + offset * 3.6
  end

  defp need_flip?(rotation) do
    90 < rotation and rotation < 270
  end

  defp negate_if_flipped(number, rotation) do
    if need_flip?(rotation),
      do: -number,
      else: number
  end

  @spec scale_values(PieChart.t()) :: [{value :: number(), label :: any()}]
  defp scale_values(%PieChart{dataset: dataset, mapping: mapping}) do
    val_accessor = dataset |> Dataset.value_fn(mapping.column_map[:value_col])
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    sum = dataset.data |> Enum.reduce(0, fn col, acc -> val_accessor.(col) + acc end)

    dataset.data
    |> Enum.map_reduce(sum, &{{val_accessor.(&1) / &2 * 100, cat_accessor.(&1)}, &2})
    |> elem(0)
  end
end
