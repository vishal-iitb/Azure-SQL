-- T-SQL based sentiment analysis on text following approach in http://dl.dropboxusercontent.com/u/4839225/twitter%20text%20mining%20with%20R.pdf
-- with trending over time

-- create scoreword table and populate from a list of word scores such as the opinion lexicon listed in http://www.cs.uic.edu/~liub/FBS/sentiment-analysis.html
CREATE TABLE [ScoreWords](
	[word] [varchar](50) NOT NULL,
	[score] [int] NOT NULL
) ON [PRIMARY]

-- create a table of stopwords and populate them with a suitable list eg check http://en.wikipedia.org/wiki/Stop_words
CREATE TABLE [StopWords](
	[stopword] [varchar](50) NOT NULL
) ON [PRIMARY]

-- I also created my own table of phrases and emoticons with sentiment scores to capture terms not present in normal word lists
CREATE TABLE [dbo].[PhraseSentiment](
	[phrase] [varchar](max) NOT NULL,
	[sentiment] [int] NOT NULL,
	[word] [varchar](50) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

-- examples of what I loaded in there were:
-- phrase		sentiment	word
-- for sure		1			forsure
-- :)			2			smiley
-- :(			-2			notsmiley
-- get stuffed	-2			getstuffed

-- some messages collected over a period of time
CREATE TABLE [Message](
	[ID] [int] NOT NULL,
	[Date] [datetime2](7) NOT NULL,
	[Message] [varchar](max) NULL,
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

-- now to split messages into words in sql server there's a few approaches - you could use the term-vector tool in ssis, or you try a trick
-- from http://www.sqlusa.com/bestpractices/training/scripts/userdefinedfunction/ - fnSplitStringListXML works ok but you need to screen out 
-- some of the characters that don't translate simply to xml

-- I fixed this by creating a view over the messages table with the offending characters removed
CREATE VIEW [Msgs]
AS
SELECT        REPLACE(REPLACE(REPLACE([Message], '&', ''), '<', ''), '>', '') AS [Message], [Date]
FROM            [Message]


-- this next part was easier to do with a cursor - at least for me...:(
-- go through temp version of msg table and update for phrases, perform substitutions and use for sentiment count
create table #tfmMsgs ( Message varchar(max), [Date] datetime)

insert into #tfmMsgs
select [Message], [Date] from Msgs

declare psCursor cursor for
	select phrase from [dbo].[phrasesentiment]

declare @newword varchar(50)
declare @phrase varchar(max)

open psCursor
fetch next from psCursor into @phrase
while (@@FETCH_STATUS <> -1)
begin
	select @newword = word
	from [phrasesentiment]
	where phrase = @phrase

	update #tfmMsgs
	set [Message] = replace([Message], @phrase, @newword)

	fetch next from psCursor into @phrase
end
close psCursor
deallocate psCursor
end

select year([Date]) as [Year], month([Date]) as [Month], Day([Date]) as [Day], sum(score) as [SumScore], count(score) as [CountScore], avg(score) as [AvgScore]
from (
	select [Date], StringLiteral
	from (
		select -- [Message], 
			[Date], 
			Words.StringLiteral
		from (select replace([Message], ' ', ',') as [Message], [Date]  from #tfmMsgs) as M
		cross apply
			dbo.fnSplitStringListXML(M.[Message], ',') as Words
		) as rawwords
	where StringLiteral not in (select stopword from stopwords) 
		and not StringLiteral = ''
	) as cleanwordscores inner join scorewords on stringliteral = word
group by year([Date]), month([Date]), day([Date])

drop table #tfmMsgs
