from os import path
from traceback import format_exc

import click

from lib import Validator, RuleDoesNotExist, RuleCannotBeParsed, FileNewLineError

DEFAULT_RULES_PATH = path.expanduser('~/dotfiles/csv_validator/rules.json')
DEFAULT_RULES_PATH = DEFAULT_RULES_PATH if path.exists(DEFAULT_RULES_PATH) else 'rules.json'

@click.group(invoke_without_command=True)
@click.option('--rules', type=click.Path(exists=True), default=DEFAULT_RULES_PATH)
@click.option('--rules-string', type=click.STRING)
@click.argument('csv', type=click.File('r'))
@click.argument('rule_name', type=click.STRING, required=False)
@click.pass_context
def run(context, csv, rule_name, rules, rules_string):
    '''csvcheck accepts a path to a csv file and will validate it against rules'''

    if rules_string:
        rules = rules_string

    context.obj = {
        'file': csv,
        'validator': get_validator(csv, rules, rule_name)
    }

    if not context.invoked_subcommand:
        errors = pretty_errors(context.obj['validator'].errors,
                               context.obj['validator'].csv_data)

        if not errors:
            click.echo('there are no errors in {}'.format(csv.name))
        else:
            print_csv_errors(errors)


@run.command()
@click.option('-l', '--line-endings/--no-line-endings', default=False)
@click.option('-e', '--remove-errors/--no-remove-errors', default=False)
@click.pass_context
def fix(context, line_endings, remove_errors):
    handle_fix(line_endings, remove_errors)


@click.pass_context
def handle_fix(context, line_endings, remove_errors):
    fixed_file_name = ''

    if line_endings:
        fixed_file_name = fix_line_endings(context.obj['file'])
    elif remove_errors:
        csv_data = context.obj['validator'].csv_data
        errors = context.obj['validator'].errors
        err_explaination = '''CONTENTS OF LINE: {line}
            INVALID CHARACTERS: {invalid}'''
        initial_msg = '''
        There are {count} errors in {file_name}.
        The first error is:
            {first_err}
        '''.format(
            count=len(errors),
            file_name=context.obj['file'].name,
            first_err=err_explaination.format(
                line=csv_data[errors[0]['line_num']],
                invalid=errors[0]['errors']))
        strategy_prompt = '''Choose a strategy:
            delete - remove the line completely
            fix    - remove the invalid characters, but keep the valid ones
            skip   - skip this line'''
        invalid_input_msg = '"{}" is not a valid strategy. Please choose from above.'

        strategy = None
        block_on_each_iteration = True
        REMOVE_LINE = 1
        STRIP_ERRORS = 2
        SKIP_LINE = 3
        allowed_inputs = {
            'd': REMOVE_LINE,
            'delete': REMOVE_LINE,
            'f': STRIP_ERRORS,
            'fix': STRIP_ERRORS,
            's': SKIP_LINE,
            'skip': SKIP_LINE
        }

        click.echo(initial_msg)

        for index, err in enumerate(errors):
            line_contents = csv_data[err['line_num']]

            if block_on_each_iteration:
                if index != 0:
                    click.echo(err_explaination.format(line=line_contents, invalid=err['errors']))
                click.echo(strategy_prompt)
                strategy = get_user_input(
                    allowed_map=allowed_inputs, invalid_msg=invalid_input_msg)
                if index == 0:
                    block_on_each_iteration = not click.confirm(
                        'Do you want to do this for the rest of the errors?')

            if strategy == STRIP_ERRORS:
                csv_data[err['line_num']] = fix_line(
                    line_contents, err, strip=True)

            elif strategy == REMOVE_LINE:
                csv_data[err['line_num']] = fix_line(line_contents, err)

            click.echo('--------------------')

        fixed_file_name = 'fixed-{}'.format(context.obj['file'].name)

        with open(fixed_file_name, 'w') as f:
            new_csv_data = ''.join('{}\n'.format(l) for l in csv_data
                                   if len(l) > 0)
            f.write(new_csv_data)

    click.echo('{} saved to current directory'.format(fixed_file_name))


def fix_line(line_contents, error, strip=False):
    '''returns the line without invalid characters or an empty string if strategy == "line"
    '''
    result = ''
    if strip:
        errors = error['errors']
        result = ''.join(c for c in line_contents if c not in errors)

    return result


def get_validator(csv, rules, rule_name):
    csv_data = csv.readlines()
    try:
        return Validator(csv_data, rules, rule_name=rule_name)

    except FileNewLineError:
        handle_file_new_line_error(promt_fix=True)
    except RuleDoesNotExist:
        handle_rule_does_not_exist_error(rule_name)
    except RuleCannotBeParsed:
        handle_rule_cannot_be_parsed_error()
    except Exception:
        print_prog_error(
            'There was a fatal error, the file was not processed.',
            tb=format_exc())


def handle_file_new_line_error(context, prompt_fix=False):
    err_message = 'CSV file has non-standard line endings and cannot be parsed as csv.'
    suggestion = 'Use the fix command to fix line endings.'
    example = 'csvcheck /path/to/file.csv rule_name fix -l'

    click.echo(err_message, err=True, color='red')

    if prompt_fix:
        if click.confirm(
                'Save new file with fixed line endings to the current directory?'
        ):
            handle_fix(True, False)
    else:
        click.echo(suggestion, err=True, color='yellow')
        click.echo(example, err=True)

        raise click.BadParameter(
            'csv file contains malformed line ending characters')


def handle_rule_does_not_exist_error(rule_name):
    err_message = 'Rule "{}" does not exist in rules json.'.format(rule_name)

    raise click.BadArgumentUsage(err_message)


def handle_rule_cannot_be_parsed_error():
    raise click.BadOptionUsage('invalid json passed into --rules-string')


def pretty_errors(errors, csv_data):
    '''returns a list of end-user friendly formatted strings describing the errors '''

    err_lines = []

    for error in errors:
        line_number = error['line_num']
        column_number = error['col_num']
        contents = csv_data[line_number]

        err_lines.append('L{line}:{col} ({errors}) --> "{contents}"'.format(
            line=line_number + 1,
            col='' if column_number == 0 else 'C{}:'.format(column_number),
            contents=contents,
            errors=error['errors']))

    return err_lines


def fix_line_endings(csv_file, out_path=None):
    '''accept file object, remove bad line endings, write to a file of the same
    basename with fixed- as a prefix

    options
        out_path: write file to a specific path instead of the same path as csv

    windows line endings can have a carriage return in addition
    to the \n char - csv has trouble parsing these line endings
    so just remove them here instead of opening the file in
    universal line endings mode since it's a big reason uploads fail
    '''
    contents = ''.join(
        line.replace('\r', '\n') for line in csv_file.readlines())

    out_file_name = 'fixed-{}'.format(csv_file.name)

    with open(out_file_name, mode='w') as out_file:
        out_file.write(contents)

    return out_file_name


def get_user_input(prompt_str='>>> ',
                   allowed_map=None,
                   invalid_msg='{} is invalid input please try again.'):
    choice = None
    while not choice:
        user_input = click.prompt(prompt_str, prompt_suffix='').lower().strip()
        choice = allowed_map.get(user_input) if allowed_map else user_input

        if not choice:
            formatted = invalid_msg.format(
                choice) if '{}' in invalid_msg else invalid_msg
            click.echo(formatted)

    return choice


def print_csv_errors(errors):
    for error in errors:
        click.echo(error)


def print_prog_error(msg, tb=None):
    click.echo(msg, err=True)
    if tb:
        for line in tb:
            click.echo(line)
