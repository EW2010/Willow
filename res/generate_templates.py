# since comptime is currently broken in beef (#1822) this is an alternative soulution

from xml.etree import ElementTree

templates = ElementTree.ElementTree(file="./templates.xml")

with open("../src/Templates.bf", 'w') as f:
    str = """using System;

namespace BindingGeneratorHpp;

static class Templates
{\n"""

    for template in templates.iter("template"):
        args = "Template.Argument[?](  "
        for arg in template.iter("argument"):
            args += f"(StringView(\"{arg.get('name')}\"), Template.Function[?](  "
            for func in arg.iter():
                if func.tag == "argument": continue
                args += f"(\"{func.tag}\", \"{func.text}\"), "
            args = args[:len(args)-2]
            args += ")), "
        args = args[:len(args)-2]
        args += ")"

        str += f"""\tpublic static let {template.get("id")} = new Template(
                text: 
\"\"\"
{template.text}
\"\"\",
                id: \"{template.get("id")}\",
                arguments: {args}
        );\n"""

    str += "}"

    f.write(str)
