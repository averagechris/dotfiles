function update_dotfiles
    set do_git_pull true
    set force_update_installed_workflows false

    for arg in $argv
        switch $arg
            case --force-update-workflows
                set force_update_installed_workflows true
            case --no-git --no-git-pull --no-pull
                set do_git_pull false
        end
    end

    pushd (pwd)

    if eval $do_git_pull
      # get latest version from github
      cd $DOTFILES
      set curr_branch (git rev-parse --abbrev-ref HEAD)
      git stash > /dev/null 2>&1
      git checkout master > /dev/null 2>&1
      git pull > /dev/null 2>&1; and echo "pulling the latest from github..."
      git checkout "$curr_branch" > /dev/null 2>&1
      git stash pop > /dev/null 2>&1
      popd
    end

    if test (uname) = "Darwin"
        set workflows_path $DOTFILES/osx/automator_workflows/
        set os_services_path ~/Library/Services

      # if force update all workflows
      if eval $force_update_installed_workflows
          # install all osx automator workflows
          cp -r $workflows_path $os_services_path; and echo "installing all available workflows"

      else
          # install only the workflows that aren't already installed
          for wf in (ls $workflows_path)
              if not contains "$wf" (ls $os_services_path)
                  cp -r "$workflows_path/$wf" $os_services_path; and echo "installing new workflow: $wf"
              end
          end
      end
    end
end
