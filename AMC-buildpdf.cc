/*

 Copyright (C) 2013-2017 Alexis Bienvenue <paamc@passoire.fr>

 This file is part of Auto-Multiple-Choice

 Auto-Multiple-Choice is free software: you can redistribute it
 and/or modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation, either version 2 of
 the License, or (at your option) any later version.

 Auto-Multiple-Choice is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Auto-Multiple-Choice.  If not, see
 <http://www.gnu.org/licenses/>.

*/

#include "buildpdf.cc"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include <string>

#ifdef NEEDS_GETLINE
  #include<minimal-getline.c>
#endif

void strip_endline(char *line) {
  char *endline;
  if((endline=strchr(line,'\r'))) *endline='\0';
  if((endline=strchr(line,'\n'))) *endline='\0';
}

int main( int argc, char** argv )
{
  size_t command_t;
  char* command=NULL;
  std::string saved_text="";
  int processing_error=0;

  double width_in_pixels,height_in_pixels;
  double dppt;
  double line_width=-1.0;

  double a,b,c,d,e,f;
  long int i,n;

#if !GLIB_CHECK_VERSION(2, 35, 0) 
  g_type_init ();
#endif

  char ch;
  while ((ch = getopt (argc, argv, "d:h:w:l:")) != -1) {
    switch (ch) {
    case 'd': dppt=atof(optarg)/72.0;break;
    case 'w': width_in_pixels=atof(optarg);break;
    case 'h': height_in_pixels=atof(optarg);break;
    case 'l': line_width=atof(optarg);break;
    }
  }

  BuildPdf PDF(width_in_pixels,height_in_pixels,dppt);
  PDF.set_line_width(line_width);

  while(getline(&command,&command_t,stdin)>=6) {
    strip_endline(command);

    printf("> %s\n",command);

    if(processing_error==0) {

      if(strncmp(command,"output ",7)==0) {
	processing_error=PDF.start_output(command+7);
      } else if(strcmp(command,"debug")==0) {
	PDF.set_debug(1);
      } else if(strncmp(command,"page png ",9)==0) {
	processing_error=PDF.new_page_from_png(command+9);
      } else if(strncmp(command,"page img ",9)==0) {
	processing_error=PDF.new_page_from_image(command+9);
      } else if(strncmp(command,"load pdf ",9)==0) {
	processing_error=PDF.load_pdf(command+9);
      } else if(sscanf(command,"page pdf %ld",&i)==1) {
	processing_error=PDF.new_page_from_pdf(i);
      } else if(strcmp(command,"matrix identity")==0) {
	PDF.identity_matrix();
      } else if(sscanf(command,"matrix %lf %lf %lf %lf %lf %lf",
		       &a,&b,&c,&d,&e,&f)==6) {
	PDF.set_matrix_to_scan(a,b,c,d,e,f);
      } else if(sscanf(command,"color %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.color(a,b,c,d);
      } else if(sscanf(command,"color %lf %lf %lf",
		       &a,&b,&c)==3) {
	PDF.color(a,b,c);
      } else if(sscanf(command,"rectangle %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4 ||
		sscanf(command,"box %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.draw_rectangle(a,b,c,d);
      } else if(sscanf(command,"circle %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.draw_circle(a,b,c,d);
      } else if(sscanf(command,"mark %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.draw_mark(a,b,c,d);
      } else if(sscanf(command,"fill %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.fill_rectangle(a,b,c,d);
      } else if(sscanf(command,"line width %lf",
		       &a)==1) {
	PDF.set_line_width(a);
      } else if(strncmp(command,"font name ",10)==0) {
    PDF.set_font(command+10);
      } else if(sscanf(command,"margin %lf",
		       &a)==1) {
	PDF.set_margin(a);
      } else if(sscanf(command,"max width %ld",
		       &i)==1) {
	PDF.set_scan_max_width(i);
      } else if(sscanf(command,"max height %ld",
		       &i)==1) {
	PDF.set_scan_max_height(i);
      } else if(strcmp(command,"embedded png")==0) {
	PDF.set_embedded_png();
      } else if(strcmp(command,"embedded jpeg")==0) {
	PDF.set_embedded_jpeg();
      } else if(sscanf(command,"jpeg quality %ld",
		       &i)==1) {
	PDF.set_jpeg_quality(i);
      } else if(sscanf(command,"text rectangle %lf %lf %lf %lf %ln",
		       &a,&b,&c,&d,&i)>=4) {
	processing_error=PDF.draw_text_rectangle(a,b,c,d,command+i);
      } else if(sscanf(command,"text %lf %lf %lf %lf %ln",
		       &a,&b,&c,&d,&i)>=4) {
	PDF.draw_text(a,b,c,d,command+i);
      } else if(sscanf(command,"text margin %ld %lf %lf %lf %ln",
		       &n,&b,&c,&d,&i)>=4) {
	PDF.draw_text_margin(n,b,c,d,command+i);
      } else if(sscanf(command,"stext margin %ld %lf %lf %lf",
		       &n,&b,&c,&d)==4) {
	PDF.draw_text_margin(n,b,c,d,saved_text.c_str());
      } else if(sscanf(command,"stext rectangle %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	processing_error=PDF.draw_text_rectangle(a,b,c,d,saved_text.c_str());
      } else if(sscanf(command,"stext %lf %lf %lf %lf",
		       &a,&b,&c,&d)==4) {
	PDF.draw_text(a,b,c,d,saved_text.c_str());
      } else if(strcmp(command,"stext begin")==0) {
	saved_text="";
	while(getline(&command,&command_t,stdin)>=0) {
	  strip_endline(command);
	  if(strcmp(command,"__END__")==0) break;
	  printf(">> %s\n",command);
	  if(saved_text.length()>0) saved_text+="\n";
	  saved_text+=command;
	}
      } else {
	printf("! ERROR: SYNTAX => %s\n",command+i);
	processing_error=2;
      }

    } else {
      printf("> SKIPPING: not responding due to previous error.\n");
    }

    printf("__END__\n");
    fflush(stdout);
  }

  PDF.close_output();

  return(processing_error);
}
