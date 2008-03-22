-- file to convert html to php code and vice versa
local _gsubPatterns = {
	['toHTML'] = {
		['color'] = {
			['pattern'] = '%[[Cc][Oo][Ll][Oo][Rr]=\'(%x%x%x%x%x%x)\'%](.-)%[/[Cc][Oo][Ll][Oo][Rr]%]',
			['result'] = '|cFF%1%2|r',
		},
		['newline'] = {
			['pattern'] = '\n',
			['result'] = '<BR/>',
		},
	},
	['fromHTML'] = {
		['color'] = {
			['pattern'] = '|cFF(%x%x%x%x%x%x)(.-)|r',
			['result'] = '[COLOR=\'%1\']%2[/COLOR]',
		},
		['newline'] = {
			['pattern'] = '<BR/>',
			['result'] = '\n',
		},
	}
}

if (not KnowItAll) then KnowItAll = {} end
function KnowItAll.toHTML(text)
	if (not text) then return nil end
	for key,tbl in pairs(_gsubPatterns.toHTML) do
		text = string.gsub(text,tbl.pattern,tbl.result)
	end
	return text
end
function KnowItAll.fromHTML(text)
	if (not text) then return nil end
	for key,tbl in pairs(_gsubPatterns.fromHTML) do
		text = string.gsub(text,tbl.pattern,tbl.result)
	end
	return text
end
