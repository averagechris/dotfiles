function update_brew_packages
    brew outdated | fzf -m -n 1 --tac --header='Select formulae to upgrade with tab' | xargs brew upgrade
end
