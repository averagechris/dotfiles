from setuptools import setup

setup(
    name='csvcheck',
    version='0.0.1',
    py_modules=['main', 'lib'],
    install_requires=['Click', 'six'],
    entry_points='''
        [console_scripts]
        csvcheck=main:run
    '''
)
