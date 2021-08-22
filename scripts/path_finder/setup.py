from setuptools import find_packages, setup

setup(
    name="path_finder",
    version="0.0.1",
    py_modules=["path_finder.cli", "path_finder.lib"],
    entry_points={"console_scripts": ["path_finder = path_finder.cli:cli"]},
    pacakges=find_packages(),
)
