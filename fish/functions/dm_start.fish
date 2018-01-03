function dm_start
	if test (uname) = "Darwin"
    python $BAY_HOME/scripts/osx/install-dfm.py
  else
    echo "Docker machine is currently only reserved for MAC OSX."
    return 1
  end
end
