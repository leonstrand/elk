 #!/bin/bash

# leonstrand@gmail.com


container_types='
consul
es
ls
kb
'

execute() {
  __command="$@"
  echo $__command
  eval $__command
}


echo
echo
command='docker ps'
execute $command

for container_type in $container_types; do
  echo
  echo $0: container_type: $container_type
  for container in $(docker ps -aqf name=$container_type); do
    command='docker start '$container
    execute $command
  done
done

echo
command='docker ps'
execute $command

echo
echo
