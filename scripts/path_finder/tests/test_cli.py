from unittest.mock import patch

import pytest
from path_finder.cli import cli
from path_finder.lib import PathFinder
from typer.testing import CliRunner


@pytest.fixture
def invoke_cli():
    def invoke(*args):
        return CliRunner(mix_stderr=False).invoke(cli, args)

    yield invoke


def test_cli_help_parent_name_no_bad_default(invoke_cli):
    """
    typer produces [default: ] if main's signature for parent_name isn't Optional
    so yeah we 💯 want to enforce a nice help message by making main's signature
    a little more annoying
    """
    result = invoke_cli("--help")

    for line in result.stdout.splitlines():
        if "--parent-name TEXT" in line:
            assert "default" not in line
            break
    else:
        pytest.fail("expected --parent-name TEXT in stdout")


@pytest.mark.parametrize(
    "arg_find_all,search_results,expected_output",
    [
        ("--no-find-all", ["one", "two"], ["one"]),
        ("--find-all", ["one", "two"], ["one", "two"]),
        ("--find-all", ["two"], ["two"]),
        ("--no-find-all", ["two", "one"], ["two"]),
        ("--find-all", [], []),
        ("--no-find-all", [], []),
    ],
)
def test_cli_find_all(arg_find_all, search_results, expected_output, invoke_cli):
    with patch.object(PathFinder, "find", return_value=iter(search_results)):
        result = invoke_cli("whatever", arg_find_all)
        assert expected_output == result.stdout.splitlines()
