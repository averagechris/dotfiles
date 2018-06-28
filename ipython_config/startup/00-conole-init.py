from collections import (
    defaultdict,
    Sequence,
)
from datetime import datetime  # noqa
import json  # noqa
import re
import subprocess

from requests import get, post  # noqa
import six


def find_credentials(search_term):

    lastpass_accounts = subprocess.Popen(
        'lpass ls',
        shell=True,
        stdout=subprocess.PIPE,
    ).stdout.readlines()
    matching_accounts = map(
        lambda account: tuple(
            # produces: (account_name, account_id)
            re.sub('[\[\]]', '', account).strip().split(' id:')
        ),
        (
            account.decode('utf-8') for account in lastpass_accounts
            if re.match(
                    '.*{}.*'.format(search_term),
                    account,
                    re.IGNORECASE
            )
        )
    )
    # TODO: allow user to fuzzy find when multiple matches
    # fzf won't work in a jupyter console :(
    account_name, account_id = list(matching_accounts)[0]
    password = subprocess.Popen(
        'lpass show -p {}'.format(account_id),
        shell=True,
        stdout=subprocess.PIPE,
    ).stdout.read().strip()

    return account_name, password


class EventbriteAPI(object):

    _BASE_EVENTBRITE_API_URL = 'https://www.{domain}.com/v3/'
    BASE_EVENTBRITE_API_URL_PROD = _BASE_EVENTBRITE_API_URL.format(domain='eventbriteapi')
    BASE_EVENTBRITE_API_URL_QA = _BASE_EVENTBRITE_API_URL.format(domain='evbqaapi')
    BASE_EVENTBRITE_API_URL_DEV = _BASE_EVENTBRITE_API_URL.format(domain='evbdevapi')
    EVENTBRITE_API_URL_MAP = {
        'prod': BASE_EVENTBRITE_API_URL_PROD,
        'qa': BASE_EVENTBRITE_API_URL_QA,
        'dev': BASE_EVENTBRITE_API_URL_DEV
    }

    def __init__(self, environment='qa', credentials=None):
        self.environment = environment
        self.base_url = self.EVENTBRITE_API_URL_MAP.get(self.environment, self.BASE_EVENTBRITE_API_URL_QA)
        self.reset_token(credentials=None)

    def reset_token(self, credentials=None):
        self.token = credentials or find_credentials('{} token'.format(self.environment))[1]

    def retrieve_n_pages(self, path, pages=None, **kwargs):
        headers = {'Authorization': 'Bearer {}'.format(self.token)}
        headers.update(kwargs.pop('headers', {}))

        results = defaultdict(list)
        has_more_items = True
        continuation_token = None
        next_page = 1

        while has_more_items:
            parameters = {}
            if continuation_token:
                parameters['continuation'] = continuation_token
            else:
                parameters['page'] = next_page

            parameters.update(kwargs.pop('params', {}))

            api_response = get(
                '{base}{path}'.format(base=self.base_url, path=path),
                headers=headers,
                params=parameters,
                **kwargs
            )
            if not api_response.ok:
                results['errors'].append({
                    'request': api_response.request,
                    'error': api_response.text
                })
                break

            response_json = api_response.json()

            pagination = response_json.pop('pagination', None)
            if pagination is None:
                break

            current_page_number = int(pagination['page_number'])

            for key, val in six.iteritems(response_json):
                if isinstance(val, Sequence):
                    results[key].extend(val)
                else:
                    results[key].append(val)

            has_more_items = pagination['has_more_items']
            if has_more_items:
                continuation_token = pagination.get('continuation')
                next_page = current_page_number + 1

            if current_page_number >= pages:
                print

            if current_page_number >= pages:
                break

        return results

    def get_events(self, pages=None, **kwargs):
        return self.retrieve_n_pages(
            '/users/me/events/',
            pages=pages,
            **kwargs
        )['events']

    def verify_response_properties(self, response, props):
        '''pass in a dictionary of properties to an optional validaion function to
        check that a response has that property and is truthy or the validation function returns something truthy '''
        def verify_properties(dictionary, props):
            errors = []
            for prop, validation_func in six.iteritems(props):
                try:
                    response_property_value = dictionary[prop]
                except KeyError:
                    errors.append({
                        'type': 'PROP_NOT_IN_RESPONSE',
                        'message': 'prop {} is not included in response'.format(prop),
                        'property_value': dictionary
                    })
                    continue

                try:
                    is_valid = validation_func(response_property_value)
                except TypeError:
                    # type error is not a vailure because the validation function is optional
                    continue
                except Exception as exc:
                    errors.append({
                        'type': 'EXCEPTION_DURING_VALIDATION',
                        'message': 'An exception was raised during validation: {}'.format(exc),
                        'property_value': response_property_value
                    })

                if not is_valid:
                    errors.append({
                        'type': 'VALIDATION_FAILIRE',
                        'message': 'validation failed for prop {} with validation func {} resulting in: {}'.format(
                            prop,
                            validation_func.__name__,
                            is_valid
                        ),
                        'property_value': response_property_value
                    })

            return errors

        errors = []
        if isinstance(response, Sequence):
            for dictionary_obj in response:
                errors.extend(verify_properties(dictionary_obj, props))
        else:
            errors = verify_properties(response, props)

        return errors

    def published_events_have_ticket_classes(self, pages=None):
        published_events = self.get_events(
            pages=pages,
            params={
                # 'status': 'live,started,ended,completed',
                'expand': 'ticket_classes'
            }
        )
        errors = self.verify_response_properties(published_events, {'ticket_classes': True})
        is_ok = not bool(errors)
        return (is_ok, len(published_events), errors)
