from pathlib import Path

from ..scripts.path_finder import PathFinder


def test_find_first_does_not_exist(tmp_path: Path):
    path_finder = PathFinder([tmp_path])
    assert not tmp_path.joinpath("needle.txt").exists()
    assert path_finder.find_first("needle") is None
    assert path_finder.find_first("needle", parent_name="anything") is None


def test_find_first_parent_exists_needle_does_not(tmp_path: Path):
    tmp_path.joinpath("parent").mkdir()
    nest_one = tmp_path.joinpath("parent/nest_one")
    nest_two = tmp_path.joinpath("parent/nest_two")

    nest_one.mkdir()
    nest_two.mkdir()

    path_finder = PathFinder([nest_one])

    assert path_finder.find_first("needle") is None
    assert path_finder.find_first("needle", parent_name="nest_two") is None


def test_find_first_success_needle_in_parent_nested(tmp_path):
    search_dir = tmp_path.joinpath("thing/nested/bin")
    bundle_dir = search_dir.parent.parent.joinpath("bundle_dir")

    search_dir.mkdir(parents=True)
    bundle_dir.mkdir(parents=True)

    bundle_dir.joinpath("Bundle.app").write_text("app here 😎")

    actual = PathFinder(paths=[search_dir]).find_first(
        "Bundle.app", parent_name="bundle_dir"
    )
    assert actual is not None and actual.exists()


def test_find_first_needle_in_path(tmp_path: Path):
    path_dir = tmp_path.joinpath("thing/nested/bin")
    path_dir.mkdir(parents=True)
    (path_dir / "file.txt").write_text("hi there :)")

    actual = PathFinder(paths=[path_dir]).find_first("file.txt")
    assert actual is not None and actual.exists()


def test_find_first_depends_on_sort_order_of_paths(tmp_path: Path):
    no_match = tmp_path.joinpath("nomatch")
    no_match.mkdir()

    match_one = tmp_path.joinpath("one/file.txt")
    match_two = tmp_path.joinpath("two/file.txt")
    match_one.parent.mkdir()
    match_two.parent.mkdir()
    match_one.write_text("hi from match_one :)")
    match_two.write_text("hi from match_two :)")

    assert (
        PathFinder([no_match, match_one, match_two]).find_first("file.txt") == match_one
    )
    assert (
        PathFinder([no_match, match_two, match_one]).find_first("file.txt") == match_two
    )


def test_find_many(tmp_path: Path):
    no_match = tmp_path.joinpath("nomatch")
    no_match.mkdir()

    match_one = tmp_path.joinpath("one/file.txt")
    match_two = tmp_path.joinpath("two/file.txt")
    match_one.parent.mkdir()
    match_two.parent.mkdir()
    match_one.write_text("hi from match_one :)")
    match_two.write_text("hi from match_two :)")

    path_finder = PathFinder([no_match.parent, match_one.parent, match_two])

    assert list(path_finder.find("file.txt")) == [match_one, match_two]


def test_find_many_paths_contain_result(tmp_path: Path):
    """if given full path PathFinder.find should return it."""
    no_match = tmp_path.joinpath("nomatch")
    no_match.mkdir()

    match_one = tmp_path.joinpath("one/file.txt")
    match_two = tmp_path.joinpath("two/file.txt")
    match_one.parent.mkdir()
    match_two.parent.mkdir()
    match_one.write_text("hi from match_one :)")
    match_two.write_text("hi from match_two :)")

    path_finder = PathFinder([no_match, match_one, match_two])

    assert list(path_finder.find("file.txt")) == [match_one, match_two]
