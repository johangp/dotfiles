# dotfiles

Dotfiles are a great way to configure system. This is my own configuration.

## Main components

- nvim
- ohmyzsh
- tmux
- kitty
- i3

## Ansible

Configuring the system after a fresh install most of the time is tedious work, repetitive
and just boring. I decide to automate the installation of all needed packages for my configuration
and set the dotfiles automatically, so in a brief I can have my configuration running on a new
fresh install.

``
ansible-playbook -i inventory bootstrap.yml
``

For testing the ansible playbook, I use Vagrant to automate the test and ensure that everything is 
going to work on a new machine. You can run `vagrant up`for running a new maschine and it will
automatically run the Ansible playbook. Then, you can check everything is working running the
`vagrant ssh` command.
