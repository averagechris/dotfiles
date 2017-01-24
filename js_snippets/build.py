import copy
# import datetime
import xml.etree.ElementTree as ET
import os
import re
import uuid


def get_snippet_content(filepath):
    with open(filepath) as file:
        return file.read()


def add_snippet_to_te_xml(dict_of_snippets):
    tree = ET.parse("./eventbrite/build/template.xml")

    snippet_nodes = tree.getroot()[0][3]

    template_node = snippet_nodes[0]
    # is the parent node which contains a <dict> node relevant nodes are
    # abbreviation string: [1]
    # label string: [7]
    # content string [11]
    # uuid string [15]

    uuids = []

    for k, v in dict_of_snippets.iteritems():
        unique_id = uuid.uuid1().__str__().upper()
        uuids.append(unique_id)

        new_node = copy.deepcopy(template_node)
        new_node[1].text = k
        new_node[7].text = k
        new_node[11].text = v
        new_node[15].text = unique_id
        snippet_nodes.append(new_node)

    snippet_nodes.remove(template_node)

    uuids_array_node = tree.getroot()[0][5]
    template_node = uuids_array_node[0]
    for u in uuids:
        new_node = copy.deepcopy(template_node)
        new_node.text = u
        uuids_array_node.append(new_node)

    uuids_array_node.remove(template_node)

    tree.write(os.path.expanduser("~/Desktop/efficiency_js_snippets.xml"))


def main():
    path_to_snippets = "./eventbrite/"
    snippets = [path_to_snippets + f for f in os.listdir(path_to_snippets)
                if "snippet.js" in f]

    abbreviation_content_dict = {}

    for snippet in snippets:
        name = re.search(r"\w+(\s\w+)?(?=_snippet\.js)", snippet)
        if name:
            name = "$" + name.group(0)
            abbreviation_content_dict[name] = get_snippet_content(snippet)

    add_snippet_to_te_xml(abbreviation_content_dict)


if __name__ == "__main__":
    main()
