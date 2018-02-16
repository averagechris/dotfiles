from __future__ import division, absolute_import, print_function
from collections import OrderedDict

import csv
import json
import os
import re
import six


class FileNewLineError(Exception):
    pass


class RuleDoesNotExist(Exception):
    pass


class RuleCannotBeParsed(Exception):
    pass


class RuleField():
    def __init__(self, field):
        # TODO set these attributes in stone and make this explicit
        for k, v in six.iteritems(field):
            setattr(self, k, v)

        if not self.caseSensitive:
            self.pattern = self.pattern.lower()

    def errors(self, check):
        return [e for e in self.errors_iter(check)]

    def errors_iter(self, check):
        if self.type in ('whitelist', 'blacklist'):
            check = check if self.caseSensitive else check.lower()
            return self._iter_chars(check)
        elif self.type in ('regex', 'regular expression'):
            return self._iter_regex(check)

    def is_valid(self, check):
        '''returns true on the first error encountered'''
        return not any(self.errors_iter(check))

    def _iter_chars(self, check):
        for c in check:
            matches = c in self.pattern

            if self.type == 'whitelist' and not matches:
                yield c

            elif self.type == 'blacklist' and matches:
                yield c

    def _iter_regex(self, check):
        flags = 0
        if not self.caseSensitive:
            flags = re.IGNORECASE

        pattern = re.compile(self.pattern, flags)
        does_not_match = pattern.sub('', check)

        if does_not_match != '':
            yield does_not_match

    def __repr__(self):
        return 'RuleField({}) -> Pattern: {}'.format(self.name, self.pattern)


class Rule():
    def __init__(self,
                 rule_name=None,
                 rules='rules.json',
                 required_rule_fields=None):

        if required_rule_fields is None:
            required_rule_fields = set([
                'name', 'pattern', 'caseSensitive', 'maxLength', 'minLength',
                'type'
            ])

        self.name = rule_name or ''
        self._field_map = self.create_field_map(
            self.parse_json(rules), rule_name, required_rule_fields)

    def __getitem__(self, key):
        index = None
        try:
            index = int(key)
        except ValueError:
            return self._field_map[key]

        keys = self._field_map.keys()
        return self._field_map[keys[index]]

    def __iter__(self):
        for rule_field in six.itervalues(self._field_map):
            yield rule_field

    def __len__(self):
        return len(self._field_map)

    def __repr__(self):
        return '<Rule({}) -> fields: {}>'.format(self.name,
                                                 self._field_map.keys())

    @staticmethod
    def create_field_map(rules_object, rule_name, required_rule_fields):
        field_map = OrderedDict()
        field_list = rules_object

        try:
            field_list = rules_object[rule_name]['fields']
        except KeyError:
            raise RuleDoesNotExist()

        except AttributeError:
            # assume a single rule - object is a list of the fields
            pass

        for field in field_list:
            # assure each field has everything needed to validate
            if set(field.keys()) < required_rule_fields:
                raise ValueError(
                    'Rules must contain these keys for validation: %s' %
                    required_rule_fields)

            field_map[field['name']] = RuleField(field)

        return field_map

    @staticmethod
    def parse_json(rules):
        '''returns parsed json from string or file'''
        if os.path.exists(rules):
            with open(rules) as f:
                rules = f.read()

        try:
            return json.loads(rules)

        except ValueError:
            raise RuleCannotBeParsed()


class Validator():
    '''Validates the contents of a csv file against a set of rules. The rules should be in json format and
        can be read in a string or file.
        PARAMS:
            csv_file_path: STRING a filepath to a csv file to validate
            rules: (Optional) STRING a string or filepath to json data that contain rules. see rules.json for formatting
            rule_name: (Optional) STRING select a rule from the rules json to use for validation
            fix_line_endings: (Optional) BOOL write a fixed version of the file if it contains non-unix line endings

        NOTES:
        arbitrary key word arguments are passed to the csv reader

        USAGE:
        Validator('~/Desktop/discounts.csv').errors

        v = Validator('~/Desktop/discounts.csv', rule_name='Event Upload', rules='~/Desktop/my_rules.json')
        errs = v.errors
        for err in errs:
            print(err)
            print(v.line(err['line_num']))
        '''

    def __init__(self, csv_data, rules, rule_name=None, **kwargs):

        self.rule = Rule(rule_name=rule_name, rules=rules)
        self.csv_data = self._clean_lines(csv_data)
        self.csv_iter = csv.reader(self.csv_data, **kwargs)
        self.errors = self._all_errors()

    def line(self, num):
        '''returns the contents of the line at the given index (not 0 indexed) and error inormation for that line'''
        num = num - 1
        line = self.csv_data[num]
        errors = filter(lambda e: e.get('line_num') == num, self.errors)
        return (line, errors)

    def _all_errors(self):
        '''iterates through all of the csv data and computes the errors, returns a list dict objects containing
        error information'''
        return [{
            'line_num': line_num,
            'col_num': col_num,
            'errors': errs
        } for line_num, col_num, errs in self._errors_iter()]

    def _errors_iter(self):
        '''lazily iterates through the csv data yielding errors for each column'''
        for line_num, row in enumerate(self.csv_iter):
            for col_num, (col, rule) in enumerate(zip(row, self.rule)):
                errors = rule.errors(col)
                if errors:
                    yield line_num, col_num, errors

    def _clean_lines(self, csv_data):

            non_unix_line_ending_char = '\r'

            if non_unix_line_ending_char in csv_data:
                raise FileNewLineError(
                    'File has a mix of non-unix line endings which cannot be parsed as csv'
                )
            else:
                # remove literal newline from each line
                return [l.replace('\n', '') for l in csv_data]

    def __repr__(self):
        return '<Validator(csv) Rule({}) -> {} Errors>'.format(self.rule.name, len(self.errors))
