proc greet {{name world}} { puts "Hello, $name!" }
greet
foreach name $argv { greet $name }
