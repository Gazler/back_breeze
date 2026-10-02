Code.require_file("support/navigation.exs", __DIR__)

{opts, args, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      width: :integer,
      height: :integer,
      items: :integer,
      iterations: :integer,
      warmup: :integer,
      cold: :boolean,
      virtual: :boolean
    ]
  )

unless args == [] and invalid == [],
  do: raise(ArgumentError, "invalid benchmark options: #{inspect(args ++ invalid)}")

BackBreeze.Bench.Navigation.run(opts)
