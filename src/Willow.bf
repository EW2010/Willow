using System;
using System.Collections;

using BindingGeneratorHpp;
using LibClang;

namespace Willow;

[AttributeUsage(.Struct | .Class)]
struct IncludeHeaderAttribute : Attribute, IOnTypeInit
{
	public enum NamingConvention
	{
		Match,
		Pascal,
		PascalButFieldsCamel
	}

	StringView filepath;
	NamingConvention naming;

	public this(StringView filepath, NamingConvention naming)
	{
		this.filepath = filepath;
		this.naming = naming;
	}

	[Comptime]
	public void OnTypeInit(Type type, Self* prev)
	{
		Clang.CXIndex index = Clang.CreateIndex();
		Clang.CXTranslationUnit unit = Clang.ParseTranslationUnit(
			index,
 			filepath.ToScopeCStr!(),
			null, 0,
			null, 0,
			.SkipFunctionBodies | .IncludeBriefCommentsInCodeCompletion
		);

		if (unit == null)
		{
			Internal.FatalError(scope $"could not load header: {filepath}");
		}

		String body = scope .();
		StringView namingStr;
		switch (naming)
		{
		case .Match: namingStr = "1:1";
		case .Pascal: namingStr = "Pascal Case";
		case .PascalButFieldsCamel: namingStr = "Pascal but Fields Camel";
		}

		Clang.VisitChildren(
			Clang.GetTranslationUnitCursor(unit),
			=> BindingGenerator.HandleCursor,
			&(body, namingStr, scope List<StringView>())
		);

		Clang.DisposeTranslationUnit(unit);
		Clang.DisposeIndex(index);

		Compiler.EmitTypeBody(type, body);
	}
}