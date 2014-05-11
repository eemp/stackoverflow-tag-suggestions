// Mihir Patel
// Prof. Sable - NLP - Independent Study

// I assummed that since we could find a part of speech tagger that worked with out system - using someone's
// stemmer was fine.

// stemmer obtained @ http://www.cs.cmu.edu/~callan/Teaching/porter.c
// stop-list obtained @ http://jmlr.csail.mit.edu/papers/volume5/lewis04a/a11-smart-stop-list/english.stop
// used http://nlp.stanford.edu/IR-book/pdf/13bayes.pdf as a naive bayes reference

#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>
#include <fstream>
#include <iostream>
#include <locale>
#include <algorithm>
#include <cmath>
#include <sstream>
#include "porter.c" 	// the stemmer

/* application mode */
#define TRAININGMODE	0
#define TESTINGMODE		1

/* usage errors */
#define MISSINGOPTS		0
#define UNEXPECTEDOPTS	1
#define UNEXPECTEDARGS	2

#define PATHLENMAX		256		//reasonable path length max

#define STOPLISTFILE	"english.stop"

using namespace std;

char *args0;

struct _classdetails
{
	unsigned short cindex;
	unsigned int tokenCount;
	unsigned int docCount;
};

typedef struct _classdetails classdetails;

const classdetails base_cd = {0, 0, 0};

struct _naivebayes
{
	unsigned int totalTerms;
	unsigned short documentCount;
	unsigned short totalLabels;
	map<string, vector<unsigned short> > condProbs; // really just counts
	map<string, classdetails > classSums;
};

typedef struct _naivebayes nbmodel;

void usage(int errorno, char *context)
{
	switch(errorno)
	{
		case MISSINGOPTS: 
			cerr << "ERROR: Invalid Arguments - expecting further arguments after \"" << context << "\" option\n";
			break;
		case UNEXPECTEDOPTS:
			cerr << "ERROR: Invalid Arguments - unexpected option \"" << context << "\"\n";
			break;
		case UNEXPECTEDARGS:
			cerr << "ERROR: Invalid Arguments - unexpected argument without context \"" << context << "\"\n";
	}
	cerr << "usage: " << args0 << " [-r traininglabelsfile] [-e testinglabelsfile] [-o outfile]\n";
	exit(-1);
}

map<string, char> stoplist;

void initStopList()
{
	ifstream list(STOPLISTFILE);
	
	if(list.is_open())
	{
		while(list.good())
		{
			string stopword;
			list >> stopword;
			
			stoplist[stopword] = 1;
		}
		
		list.close();
	}
	else
		cerr << "ERROR: Unable to load stop list file " << STOPLISTFILE << endl;
		// ok to continue - just won't check against stoplist
}

inline int isUndesiredChar(int c)
{
	//return isspace(c);
	return !isalnum(c);
}

inline void stripEdgePunct(string &s)
{
	// strip from front
	for(string::iterator it = s.begin(); it != s.end(); )
	{
		if(ispunct(*it))
			s.erase(it);
		else
			break;
	}

	// strip from end
	for(string::reverse_iterator it = s.rbegin(); it != s.rend(); it++)
	{
		if(ispunct(*it))
			s.erase(--(it.base()));
		else
			break;
	}
}

inline void replaceNumbers(string &s)
{
	istringstream iss(s);
	int val;
	string leftover;

	iss >> val;
	iss >> leftover;

	if(val == 0)
		return;

	if(leftover.size()){ // ordinal or cardinal... whatever th, nd, rd tags are for
		s = leftover;
		return;
	}

	if(val / 1900 == 1 || val / 2000 == 1)
		s = "year";
	else
		s = "number";
}

void stem_s(string &token)
{
	// stemming
	char *token_c = (char *)token.c_str();
	int newend = stem(token_c, 0, token.size()-1);
	token_c[newend+1] = '\0';
	string stemmedtoken(token_c);
	
	if(token.compare(stemmedtoken) != 0)
		token = stemmedtoken;
		
}

// transformToken takes a token and checks against a list of stop words, converts to lower case, 
// removes punctuation and odd white space, and uses a stemmer obtained from source mentioned above
void transformToken(string &token)
{
	// just consider alpha numeric
	token.erase(remove_if(token.begin(), token.end(), isUndesiredChar), token.end());
	// just consider lowercase
	transform(token.begin(), token.end(), token.begin(), ::tolower);
	
	// remove edge punctuation
	//stripEdgePunct(token);

	// stemming
	stem_s(token);

	// check against stoplist
	if(stoplist.find(token) != stoplist.end())
	{
		token = "";
		return; //ignore stoplist words
	}

	// deal with numbers
	//replaceNumbers(token);
}

void processDoc(string &file, string &label, nbmodel &nbm)
{
	ifstream doc(file.c_str());
	
	if(doc.is_open())
	{
		while(doc.good())
		{
			string token;
			
			doc >> token;
			
			transformToken(token);
			
			if(token.compare("") == 0)
				continue;
			
			if(nbm.condProbs.find(token) == nbm.condProbs.end())
			{
				nbm.totalTerms++;
				nbm.condProbs[token].resize(nbm.totalLabels, 1); // add-one or laplace smoothing
				//cerr << token << endl;
			}	
			nbm.classSums[label].tokenCount++;
			nbm.condProbs[token][nbm.classSums[label].cindex]++;
		}
	}
	else
	{
		cerr << "ERROR: Unable to open a document in training corpus - " << file << endl;
		// warn and ok to continue
		nbm.documentCount--;
	}
}

void train(char *file, nbmodel &modeltotrain)
{
	modeltotrain.totalLabels = 0;
	modeltotrain.documentCount = 0;
	modeltotrain.totalTerms = 0;
	
	ifstream trainingIn(file);
	
	if(trainingIn.is_open())
	{
		int nextAvailableIndex = 0;
		vector< vector<string> > docstoprocess;
		while(trainingIn.good())
		{
			string traindoc, label;
			
			trainingIn >> traindoc;
			trainingIn >> label;
			
			// ignore final newline
			if(label.compare("") == 0)
				continue;
			
			if(modeltotrain.classSums.find(label) != modeltotrain.classSums.end())
				modeltotrain.classSums[label].docCount++;
			else {
				modeltotrain.totalLabels++;
				modeltotrain.classSums[label].docCount = 1;
				modeltotrain.classSums[label].cindex = nextAvailableIndex++;
				modeltotrain.classSums[label].tokenCount = 0;
			}
			modeltotrain.documentCount++;
			
			// can't process till all labels are known
			//processDoc(traindoc, label, modeltotrain);
			vector<string> doclabel; doclabel.push_back(traindoc); doclabel.push_back(label);
			docstoprocess.push_back(doclabel);
		}
		
		for(int i = 0; i < docstoprocess.size(); i++)
			processDoc(docstoprocess[i][0], docstoprocess[i][1], modeltotrain);
		
		trainingIn.close();
	}
	else
	{
		cerr << "ERROR: Unable to read " << file << " training set file\n"; 
		exit(-1);
	}
}

string classifyDoc(string file, nbmodel &trainedmodel)
{
	string label;
	ifstream doc(file.c_str());
	
	if(doc.is_open())
	{
		vector<long double> probs;
		probs.resize(trainedmodel.totalLabels, 0);
		
		while(doc.good())
		{
			string token;
			
			doc >> token;
			
			transformToken(token);
			
			if(token.compare("") == 0)
				continue;
			
			if(trainedmodel.condProbs.find(token) != trainedmodel.condProbs.end())
			{
				for (map<string, classdetails>::iterator it=trainedmodel.classSums.begin(); it!=trainedmodel.classSums.end(); ++it) {
					probs[trainedmodel.classSums[it->first].cindex] += 
						log10((long double)trainedmodel.condProbs[token][trainedmodel.classSums[it->first].cindex]/
							(trainedmodel.totalTerms + trainedmodel.classSums[it->first].tokenCount));
				}
			}
			else
			{
				for (map<string, classdetails>::iterator it=trainedmodel.classSums.begin(); it!=trainedmodel.classSums.end(); ++it)
					probs[trainedmodel.classSums[it->first].cindex] -= 
						log10(1.0/(trainedmodel.totalTerms + trainedmodel.classSums[it->first].tokenCount));
			}
		}
		
		map<string, classdetails>::iterator it=trainedmodel.classSums.begin();
		probs[trainedmodel.classSums[it->first].cindex] += 
			log10((long double)trainedmodel.classSums[it->first].docCount/trainedmodel.documentCount);
		
		long double maxscore = probs[trainedmodel.classSums[it->first].cindex];
		label = it->first;
		
		it++;
		
		for (; it!=trainedmodel.classSums.end(); ++it)
		{
			probs[trainedmodel.classSums[it->first].cindex] += 
				log10((long double)trainedmodel.classSums[it->first].docCount/trainedmodel.documentCount);
				
			if(probs[trainedmodel.classSums[it->first].cindex] > maxscore)
			{
				maxscore = probs[trainedmodel.classSums[it->first].cindex];
				label = it->first;
			}
		}
		
		doc.close();
	}
	else
		cerr << "ERROR: Unable to open a document in training corpus - " << file << endl;
		
	return label;
}

void test(char *file, nbmodel &trainedmodel, stringstream &results)
{
	ifstream testingIn(file);
	
	if(testingIn.is_open())
	{
		int nextAvailableIndex = 0;
		while(testingIn.good())
		{
			string testdoc, label;
			
			testingIn >> testdoc;
			
			if(testdoc.compare("") == 0)
				continue;
			
			label = classifyDoc(testdoc, trainedmodel);
			results << testdoc << " " << label << endl;
		}
		
		testingIn.close();
	}
	else
	{
		cerr << "ERROR: Unable to read " << file << " testing set file\n"; 
		exit(-1);
	}
}

void loadStats(char *file)
{
	// unimplemented - unnecessary
}

void writeStats(char *file)
{
	// unimplemented - unnecessary
}

int main(int argc, char *argv[])
{
	int i;
	char *training_filename = NULL, *testing_filename = NULL, 
		*stats_filename = NULL,	*output_filename = NULL, mode = TRAININGMODE;
	nbmodel tc;

	args0 = argv[0];
	
	initStopList();
	
	for(i = 1; i < argc; i++)
	{
		if(argv[i][0] == '-')
		{
			if(i == argc-1 || i != argc-1 && argv[i+1][0] == '-')
			{
				switch(argv[i][1])
				{
					case 'r': case 'e': case 'o': usage(MISSINGOPTS, argv[i]);
					default: usage(UNEXPECTEDOPTS, argv[i]);
				}
			}
			else if(strlen(argv[i]) != 2)
				usage(UNEXPECTEDOPTS, argv[i]);
			else
			{
				switch(argv[i][1])
				{
					case 'r': training_filename = argv[++i]; break;
					case 'e': testing_filename = argv[++i]; break;
					case 'o': output_filename = argv[++i]; break;
					default: usage(UNEXPECTEDOPTS, argv[i]);
				}
			}
		}
		else
			usage(UNEXPECTEDARGS, argv[i]);
	}

	if(!training_filename)
	{
		training_filename = (char *)malloc(PATHLENMAX);
		cout << "Please input the path to the file containing the training set and corresponding labels: ";
		fgets(training_filename, PATHLENMAX, stdin);
		training_filename[strlen(training_filename) - 1] = '\0';
	}
	
	if(stats_filename)
		loadStats(stats_filename);
		
	train(training_filename, tc);
	
	if(stats_filename)
		writeStats(stats_filename);

testing:
	
	if(!testing_filename)
	{
		testing_filename = (char *)malloc(PATHLENMAX);
		cout << "Please input the path to the file containing the testing set and corresponding labels: ";
		fgets(testing_filename, PATHLENMAX, stdin);
		testing_filename[strlen(testing_filename) - 1] = '\0';
	}

	stringstream results;
	test(testing_filename, tc, results);

	if(!output_filename)
	{
		output_filename = (char *)malloc(PATHLENMAX);
		cout << "Please input the path to the file to which output can be written: ";
		fgets(output_filename, PATHLENMAX, stdin);
		output_filename[strlen(output_filename) - 1] = '\0';
	}
	
	string output = results.str();
	
	ofstream out(output_filename);
	if(out.is_open())
	{
		out << output;
	}
	else
	{
		cerr << "ERROR: Unable to open file " << output_filename << " to write results to" << endl;
		return -1;
	}
	
	return 0;
}

// g++ -w tc.cpp -o mptc && ./mptc -r corpus1_train.labels -e corpus1_test.list -o corpus1_predictions.labels && perl analyze.pl corpus1_predictions.labels corpus1_test.labels
// g++ -w tc.cpp -o mptc && ./mptc -r corpus2_training.labels -e corpus2_tuning.list -o corpus2_predictions.labels && perl analyze.pl corpus2_predictions.labels corpus2_tuning.labels
// g++ -w tc.cpp -o mptc && ./mptc -r corpus3_training.labels -e corpus3_tuning.list -o corpus3_predictions.labels && perl analyze.pl corpus3_predictions.labels corpus3_tuning.labels


