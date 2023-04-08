using System;
using System.Collections;
using System.IO;
using System.Diagnostics;

using LibClang;

namespace BindingGeneratorHpp;

class BindingGenerator : Compiler.Generator
{
	public override String Name => "Binding of a Header (Willow)";

	public override void InitUI()
	{
		AddFilePath("header", "Path to Header", "");
		AddCombo("naming", "Naming Convention", "Pascal Case", StringView[?]("1:1", "Pascal Case", "Pascal but Fields Camel"));
	}

	typealias Data = (String outText, StringView naming, List<StringView> nest);
	private static Clang.CXChildVisitResult HandleCursor(Clang.CXCursor cursor, Clang.CXCursor parent, Clang.CXClientData rawData)
	{
		StringView CXString2StringView(Clang.CXString str)
		{
			StringView output = .(Clang.GetCString(str));
			Clang.DisposeString(str);
			return output;
		}

		(StringView output, bool @const) GetBeefType(Clang.CXType type)
		{
			bool @const = Clang.IsConstQualifiedType(type) > 0;
			switch (type.kind)
			{
			case .CXType_Char_S:
				return ("c_char", @const);
			case .CXType_Char16:
				return ("char16", @const);
			case .CXType_Char32:
				return ("char32", @const);
			case .CXType_WChar:
				return ("c_wchar", @const);
			case .CXType_Short:
				return ("c_short", @const);
			case .CXType_Int:
				return ("c_int", @const);
			case .CXType_Long:
				return ("c_long", @const);
			case .CXType_LongLong:
				return ("c_longlong", @const);
			case .CXType_Float:
				return ("float", @const);
			case .CXType_Double:
				return ("double", @const);
			case .CXType_LongDouble:
				return ("c_longdouble", @const);
			case .CXType_Char_U:
				return ("c_uchar", @const);
			case .CXType_UShort:
				return ("c_ushort", @const);
			case .CXType_UInt:
				return ("c_uint", @const);
			case .CXType_ULong:
				return ("c_ulong", @const);
			case .CXType_ULongLong:
				return ("c_ulonglong", @const);

			case .CXType_Pointer:
				return (scope $"({GetBeefType(Clang.GetPointeeType(type)).output}*)", @const);
			case .CXType_RValueReference, .CXType_LValueReference:
				return (scope $"(ref {GetBeefType(Clang.GetPointeeType(type)).output})", @const);

			case .CXType_Elaborated: // struct enum class
				return (scope $"type_{CXString2StringView(Clang.GetTypeSpelling(type)).GetHashCode()}", @const);
			default:
			}
		}

		StringView ConvertName(StringView naming, StringView thing, bool field = false)
		{
			switch (naming)
			{
			case "1:1":
				return thing;
			case "Pascal Case":
				String output = scope .();
				for (var part in thing.Split('_'))
				{
					output.AppendF("{}{}", part[0].ToUpper, part..RemoveFromStart(1));
				}
			case "Pascal but Fields Camel":
				if (field)
				{
					var tmp = ConvertName("Pascal Case", thing);
					tmp[0] = tmp[0].ToLower;
					return tmp;
				}
				else return ConvertName("Pascal Case", thing);
			}
		}

		void CreateInternalAlias(String str, List<StringView> nest, int hashed, StringView aliased)
		{
			for (let n in nest)
			{
				str.Append("}");
			}

			str.AppendF($"\ninternal typealias type_{hashed} = {aliased};\n");

			for (let n in nest)
			{
				str.AppendF($$"extention {{n}} {\n");
			}
		}
		
		Data* data = (.)rawData;

		switch (Clang.GetCursorKind(cursor))
		{
		case .CXCursor_Namespace:
			Clang.VisitChildren(
				cursor,
				=> HandleCursor,
				rawData
			);
		case .CXCursor_StructDecl, .CXCursor_ClassDecl:
		case .CXCursor_FunctionDecl, .CXCursor_CXXMethod:

		case .CXCursor_Constructor, .CXCursor_Destructor:
		case .CXCursor_TypeAliasDecl, .CXCursor_TypedefDecl:
			Clang.CXType type = Clang.GetTypedefDeclUnderlyingType(cursor);
			Templates.TypeAlias.Inject(
				data.outText,
				scope Dictionary<StringView, StringView>()
					..Add("name", ConvertName(data.naming, CXString2StringView(Clang.GetCursorSpelling(cursor))))
					..Add("type", GetBeefType(type).output)
					..Add("documentation", .(Clang.GetCString(Clang.Cursor_GetRawCommentText(cursor))))
			);
		case .CXCursor_TranslationUnit:
			String body = scope .();
			StringView name = ConvertName(data.naming, CXString2StringView(Clang.GetCursorSpelling(cursor)));
			Clang.VisitChildren(
				cursor,
				=> HandleCursor,
				&(body, data.naming, data.nest..Add(name))
			);

			Templates.Library.Inject(
				data.outText,
				scope Dictionary<StringView, StringView>()
					..Add("name", name)
					..Add("body", body)
					..Add("documentation", "")
			);
		default:
		}

		return .Contine;
	}

	public override void Generate(String outFileName, String outText, ref Flags generateFlags)
	{
		Templates.BoilerPlate.Inject(
			outText,
			scope Dictionary<StringView, StringView>()..Add("version", "1.0.0")
		);

		Clang.CXIndex index = Clang.CreateIndex();
		Clang.CXTranslationUnit unit = Clang.ParseTranslationUnit(
			index,
			mParams["header"].ToScopeCStr!(),
			null, 0,
			null, 0,
			.SkipFunctionBodies | .IncludeBriefCommentsInCodeCompletion
		);

		if (unit == null)
		{
			Fail("Header could not be loaded");
			return;
		}

		Clang.CXCursor cursor = Clang.GetTranslationUnitCursor(unit);

		HandleCursor(cursor, cursor, &(outText, mParams["naming"], scope List<StringView>()));

		Clang.DisposeIndex(index);
		Clang.DisposeTranslationUnit(unit);
	}
}

class Template
{
	public typealias Function = (StringView name, StringView value);
	public typealias Argument = (StringView name, Span<Function>);

	public StringView Text;
	public StringView ID;
	public Span<Argument> Arguments;

	public void Inject(String str, Dictionary<StringView, StringView> args)
	{
		String tmp = scope .()..Append(Text);

		for (let arg in Arguments)
		{
			String inject = scope .(args[arg.name]);

			for (let func in arg.1)
			{
				switch (func.name)
				{
				case "prefixln":
					inject.Replace("\n", "\n"..Append(func.value));

				}
			}

			tmp..Replace(scope $$"{{{arg.name}}}", inject)..Replace("{{", "{")..Replace("}}", "}");
		}

		str.Append(tmp);
	}

	public this(StringView text, StringView id, Span<Argument> arguments) { Text = text; ID = id; Arguments = arguments; }
}