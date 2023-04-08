using System;
using System.Collections;
using System.IO;
using System.Diagnostics;

using LibClang;

namespace BindingGeneratorHpp;

class BindingGenerator : Compiler.Generator
{
	public override String Name => "Binding (Willow)";

	public override void InitUI()
	{
		AddFilePath("header", "Path to Header", "");
		AddCombo("naming", "Naming Convention", "Pascal Case", StringView[?]("1:1", "Pascal Case", "Pascal but Fields Camel"));
	}

	typealias Data = (String outText, StringView naming, List<StringView> nest);
	public static Clang.CXChildVisitResult HandleCursor(Clang.CXCursor cursor, Clang.CXCursor parent, Clang.CXClientData rawData)
	{
		StringView CXString2StringView(Clang.CXString str)
		{
			StringView output = .(Clang.GetCString(str));
			Clang.DisposeString(str);
			return output;
		}

		(StringView output, StringView constant) GetBeefType(Clang.CXType type)
		{
			let constant = Clang.IsConstQualifiedType(type) > 0 ? "true" : "false";
			switch (type.kind)
			{
			case .CXType_Char_S:
				return ("c_char", constant);
			case .CXType_Char16:
				return ("char16", constant);
			case .CXType_Char32:
				return ("char32", constant);
			case .CXType_WChar:
				return ("c_wchar", constant);
			case .CXType_Short:
				return ("c_short", constant);
			case .CXType_Int:
				return ("c_int", constant);
			case .CXType_Long:
				return ("c_long", constant);
			case .CXType_LongLong:
				return ("c_longlong", constant);
			case .CXType_Float:
				return ("float", constant);
			case .CXType_Double:
				return ("double", constant);
			case .CXType_LongDouble:
				return ("c_longdouble", constant);
			case .CXType_Char_U:
				return ("c_uchar", constant);
			case .CXType_UShort:
				return ("c_ushort", constant);
			case .CXType_UInt:
				return ("c_uint", constant);
			case .CXType_ULong:
				return ("c_ulong", constant);
			case .CXType_ULongLong:
				return ("c_ulonglong", constant);

			case .CXType_Pointer:
				return (scope $"({GetBeefType(Clang.GetPointeeType(type)).output}*)", constant);
			case .CXType_RValueReference, .CXType_LValueReference:
				return (scope $"(ref {GetBeefType(Clang.GetPointeeType(type)).output})", constant);

			case .CXType_Elaborated: // struct enum class
				return (scope $"type_{CXString2StringView(Clang.GetTypeSpelling(type)).GetHashCode()}", constant);
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
			StringView callingConv;
			switch (Clang.GetCursorCallingConv(cursor))
			{
			case .CXCallingConv_C:
				callingConv = "Cdecl";
			case .CXCallingConv_X86StdCall:
				callingConv = "StdCall";
			case .CXCallingConv_X86FastCall:
				callingConv = "FastCall";
			default:
				callingConv = "Unspecified";
			}

			let name = CXString2StringView(Clang.GetCursorSpelling(cursor));
			let type = GetBeefType(Clang.GetCursorType(cursor));
			let docs = CXString2StringView(Clang.Cursor_GetRawCommentText(cursor));

			String parameters = scope .();
			let num = Clang.Cursor_GetNumArguments(cursor);
 			for (let i < num)
			{
				let param = Clang.Cursor_GetArgument(cursor, (.)i);
				let p_type = GetBeefType(Clang.GetCursorType(param));
				let p_name = ConvertName(data.naming, CXString2StringView(Clang.GetCursorSpelling(param)));

				Templates.Parameter.Inject(
					parameters,
					scope Dictionary<StringView, StringView>()
						..Add("name", p_name)
						..Add("type", p_type.output)
						..Add("const", p_type.constant)
						..Add("params", Clang.GetCursorKind(param) == .CXCursor_VarDecl ? "true" : "false")
						..Add("last", i == num - 1 ? "true" : "false")
				);
			}

			Templates.Function.Inject(
				data.outText,
				scope Dictionary<StringView, StringView>()
					..Add("mangle_name", name)
					..Add("c_mangling", Clang.GetCursorLinkage(cursor) == .CXLinkage_UniqueExternal ? "false" : "true")

					..Add("return", type.output)
					..Add("return_const", type.constant)

					..Add("name", ConvertName(data.naming, name))
					..Add("parameters", parameters)
					..Add("calling_conv", callingConv)

					..Add("documentation", docs)
			);
		case .CXCursor_Constructor, .CXCursor_Destructor:
			StringView callingConv;
			switch (Clang.GetCursorCallingConv(cursor))
			{
			case .CXCallingConv_C:
				callingConv = "Cdecl";
			case .CXCallingConv_X86StdCall:
				callingConv = "StdCall";
			case .CXCallingConv_X86FastCall:
				callingConv = "FastCall";
			default:
				callingConv = "Unspecified";
			}

			let docs = CXString2StringView(Clang.Cursor_GetRawCommentText(cursor));

			String parameters = scope .();
			let num = Clang.Cursor_GetNumArguments(cursor);
			for (let i < num)
			{
				let param = Clang.Cursor_GetArgument(cursor, (.)i);
				let p_type = GetBeefType(Clang.GetCursorType(param));
				let p_name = ConvertName(data.naming, CXString2StringView(Clang.GetCursorSpelling(param)));

				Templates.Parameter.Inject(
					parameters,
					scope Dictionary<StringView, StringView>()
						..Add("name", p_name)
						..Add("type", p_type.output)
						..Add("const", p_type.constant)
						..Add("params", Clang.GetCursorKind(param) == .CXCursor_VarDecl ? "true" : "false")
						..Add("last", i == num - 1 ? "true" : "false")
				);
			}

			Templates.Constructor.Inject(
				data.outText,
				scope Dictionary<StringView, StringView>()
					..Add("destructor", Clang.GetCursorKind(cursor) == .CXCursor_Destructor ? "true" : "false")
					..Add("c_mangling", Clang.GetCursorLinkage(cursor) == .CXLinkage_UniqueExternal ? "false" : "true")
					..Add("parameters", parameters)
					..Add("calling_conv", callingConv)
					..Add("documentation", docs)
			);
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
		case .CXCursor_InclusionDirective:
		default:
		}

		return .Contine;
	}

	public override void Generate(String outFileName, String outText, ref Flags generateFlags)
	{
		outFileName.Append(mParams["header"]);
		generateFlags = .AllowRegenerate;
		ParseAndGen(outText, mParams["header"]);
	}

	public void ParseAndGen(String outText, StringView filename)
	{
		Templates.BoilerPlate.Inject(
			outText,
			scope Dictionary<StringView, StringView>()..Add("version", "1.0.0")
		);

		Clang.CXIndex index = Clang.CreateIndex();
		Clang.CXTranslationUnit unit = Clang.ParseTranslationUnit(
			index,
			filename.ToScopeCStr!(),
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