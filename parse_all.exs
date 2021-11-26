namespace = DocPrepper.parse_directory("/home/icy/docs/codes/IceDragon/minetest-dev/minetest-games/HarmoniaScarredWorld/mods")

output_dir = "tmp/web"

File.mkdir_p output_dir

render_namespace_file = fn render_namespace_file, name, namespace, root_path ->
  IO.puts "RENDER NAMESPACE #{inspect root_path} #{name}"
  path = root_path ++ [name]
  filename = Path.join([output_dir | path] ++ ["index.html"])

  blob = DocPrepper.HTML.render_namespace(
    name: name,
    namespace: namespace,
    path: path
  )

  File.mkdir_p Path.dirname(filename)

  File.write!(filename, blob)

  names = Map.keys(namespace.namespaces) ++ Map.keys(namespace.classes)
  Enum.each(Enum.uniq(names), fn ns_name ->
    child_namespace = namespace.namespaces[ns_name]
    render_namespace_file.(render_namespace_file, ns_name, child_namespace, path)
  end)
end

render_namespace_file.(render_namespace_file, "_G", namespace, [])
